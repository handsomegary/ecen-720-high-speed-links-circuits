from __future__ import print_function
import argparse, datetime, hashlib, json, math, os, re, subprocess, sys
from parse_psf import parse_sweep, parse_scalar

def nfmt(v): return '%.14g' % v

def mos(name, nodes, cfg, role='input'):
    device=cfg['device']
    model=device['model']
    dims=cfg.get(role+'_geometry',cfg['input_geometry'])
    parameters=dict(device.get('fixed_parameters',{}))
    parameters.update(dims)
    return '%s (%s) %s %s' % (name,' '.join(nodes),model,' '.join('%s=%s'%(k,nfmt(v) if isinstance(v,(float,int)) else v) for k,v in sorted(parameters.items())))

def prbs(bits=2048):
    state=0x7f; out=[]
    for _ in range(bits):
        out.append(state & 1)
        bit=((state>>6)^(state>>5))&1
        state=((state<<1)&0x7f)|bit
    return out

def make_netlist(c):
    model=c['model_file']; section=c['section']; n=c.get('stages',5)
    vd=c['vdd']; it=c['tail_current_a']; rl=c['rl_ohm']; vcm=c.get('input_cm_v',vd-it*rl/2)
    s=['simulator lang=spectre','global 0','include "%s" section=%s'%(model,section),
       'VDD (vdd 0) vsource dc='+nfmt(vd),'VCM (vcm 0) vsource dc='+nfmt(vcm)]
    mode=c.get('mode','ac')
    vin='VIN (stim 0) vsource dc=0 mag=1'
    if mode=='tran':
        bits=prbs(c.get('bits',2048)); ui=1e-10; edge=c.get('edge_s',1e-11); amp=c.get('input_vppd',.01)/2
        values=[0,amp*(2*bits[0]-1)]
        if c.get('neutral_initial_symbol',False):
            # Keep the transient initial operating point at zero differential
            # drive. Starting directly at a PRBS level charges the AC-coupling
            # capacitors against a held symbol before the data stream begins.
            values=[0,0,edge/2,amp*(2*bits[0]-1)]
        for k in range(1,len(bits)):
            old=amp*(2*bits[k-1]-1); new=amp*(2*bits[k]-1)
            if old!=new: values += [k*ui-edge/2,old,k*ui+edge/2,new]
        values += [len(bits)*ui,amp*(2*bits[-1]-1)]
        vin+=' type=pwl wave=['+' '.join(nfmt(v) for v in values)+']'
    s += [vin,'EP (srcp vcm stim 0) vcvs gain=0.5','EN (srcn vcm stim 0) vcvs gain=-0.5']
    servo=c.get('servo',False)
    if servo:
        # For an odd number of inverting cells this output-to-input DC feedback is negative.
        assert n%2==1
        s += ['CINP (srcp inp) capacitor c='+nfmt(c.get('input_c_f',200e-12)),
              'CINN (srcn inn) capacitor c='+nfmt(c.get('input_c_f',200e-12)),
              'RFBP (outp inp) resistor r='+nfmt(c.get('feedback_r_ohm',5e6)),
              'RFBN (outn inn) resistor r='+nfmt(c.get('feedback_r_ohm',5e6))]
    else:
        s += ['EINP (inp 0 srcp 0) vcvs gain=1','EINN (inn 0 srcn 0) vcvs gain=1']
    if c.get('offset_v',0):
        s += ['VOFF (gfirst inp) vsource dc='+nfmt(c['offset_v'])]
    if c.get('tail_type','ideal')=='mos':
        # Diode-connected reference and real tail devices; reference source is ideal at this stage.
        refcfg=dict(c)
        refcfg['reference_geometry']=c.get('reference_geometry',c['tail_geometry'])
        s += ['IREF (vdd vb) isource dc='+nfmt(c.get('reference_current_a',it)),mos('MREF',['vb','vb','0','0'],refcfg,'reference')]
    lp=c.get('peak_l_h',0)
    a,b='inp','inn'
    for k in range(1,n+1):
        stagecfg=c
        if c.get('stage_input_geometries'):
            assert len(c['stage_input_geometries'])==n
            stagecfg=dict(c);stagecfg['input_geometry']=c['stage_input_geometries'][k-1]
        p,q=('outp','outn') if k==n else ('p%d'%k,'n%d'%k)
        tail='t%d'%k
        loadp,loadq=p,q
        if lp>0:
            loadp,loadq='lp%d'%k,'ln%d'%k
            ipp,ipn='ilp%d'%k,'iln%d'%k
            s += ['LP%d (%s %s) inductor l=%s'%(k,loadp,ipp,nfmt(lp)),
                  'LN%d (%s %s) inductor l=%s'%(k,loadq,ipn,nfmt(lp)),
                  'RLP%d (%s %s) resistor r=%s'%(k,ipp,p,nfmt(c.get('peak_r_ohm',5))),
                  'RLN%d (%s %s) resistor r=%s'%(k,ipn,q,nfmt(c.get('peak_r_ohm',5)))]
        s += ['RP%d (vdd %s) resistor r=%s'%(k,loadp,nfmt(rl)),
              'RN%d (vdd %s) resistor r=%s'%(k,loadq,nfmt(rl)),
              mos('MP%d'%k,[p,'gfirst' if k==1 and c.get('offset_v',0) else a,tail,'0'],stagecfg),mos('MN%d'%k,[q,b,tail,'0'],stagecfg)]
        if c.get('tail_type','ideal')=='ideal': s += ['IT%d (%s 0) isource dc=%s'%(k,tail,nfmt(it))]
        elif c['tail_type']=='resistor': s += ['RT%d (%s 0) resistor r=%s'%(k,tail,nfmt(c['tail_r_ohm']))]
        else: s += [mos('MT%d'%k,[tail,'vb','0','0'],c,'tail')]
        if c.get('node_extra_c_f',0):
            s += ['CP%d (%s 0) capacitor c=%s'%(k,p,nfmt(c['node_extra_c_f'])),
                  'CN%d (%s 0) capacitor c=%s'%(k,q,nfmt(c['node_extra_c_f']))]
        a,b=p,q
    internal=['p%d'%k for k in range(1,n)]+['n%d'%k for k in range(1,n)]+['t%d'%k for k in range(1,n+1)]
    s += ['CLOADP (outp 0) capacitor c='+nfmt(c.get('load_c_per_output_f',20e-15)),
          'CLOADN (outn 0) capacitor c='+nfmt(c.get('load_c_per_output_f',20e-15)),
          'opts options temp=%s reltol=1e-5 vabstol=1e-8 iabstol=1e-12 gmin=1e-15'%c.get('temperature_c',27),
          'saveOpt options save=selected currents=selected','save outp outn inp inn srcp srcn stim vdd VDD:p '+' '.join(internal),
          'dcOp dc write="spectre.dc"','dcOpInfo info what=oppoint where=rawfile']
    if c.get('offset_v',0):s += ['save gfirst']
    if mode=='tran':
        tr='tran tran stop=%s maxstep=1p errpreset=conservative'%nfmt(c.get('bits',2048)*1e-10)
        if c.get('transient_noise',False):tr+=' noisefmax=50G noisefmin=10M noiseseed=731'
        s += [tr]
    elif mode!='dc':
        s += ['ac ac start=1k stop=200G dec=80',
              'noise (outp outn) noise start=1k stop=200G dec=80 iprobe=VIN']
    return '\n'.join(s)+'\n'

def trap(xs,ys):return sum((xs[j+1]-xs[j])*(ys[j+1]+ys[j])/2 for j in range(len(xs)-1))

def measure(run,c):
    a=parse_sweep(os.path.join(run,'psf','ac.ac'),required_signals=['outp','outn'])
    f=[r['axis_value'] for r in a['rows']]
    h=[complex(*r['values']['outp'])-complex(*r['values']['outn']) for r in a['rows']]
    mag=[abs(v) for v in h]
    mid=min(range(len(f)),key=lambda j:abs(math.log(f[j]/1e8)))
    gain=mag[mid]; target=gain/math.sqrt(2)
    bw=None
    for j in range(mid,len(f)-1):
        if mag[j]>=target and mag[j+1]<target:
            w=(math.log(target)-math.log(mag[j]))/(math.log(mag[j+1])-math.log(mag[j]))
            bw=math.exp(math.log(f[j])+w*math.log(f[j+1]/f[j]));break
    # A multi-stage global feedback path can produce RF peaking.  Also report
    # the upper -3 dB edge relative to the actual maximum, so a suppressed
    # 100 MHz reference cannot make a narrow response look wider.
    peak=max(mag); peak_i=mag.index(peak); peak_target=peak/math.sqrt(2); peak_bw=None
    for j in range(peak_i,len(f)-1):
        if mag[j]>=peak_target and mag[j+1]<peak_target:
            weight=(math.log(peak_target)-math.log(mag[j]))/(math.log(mag[j+1])-math.log(mag[j]))
            peak_bw=math.exp(math.log(f[j])+weight*math.log(f[j+1]/f[j]));break
    no=parse_sweep(os.path.join(run,'psf','noise.noise'),required_signals=['out','in'])
    nf=[r['axis_value'] for r in no['rows']]
    # Spectre 'out' and 'in' are V/sqrt(Hz) amplitudes, confirmed from installed help/PSF units.
    ov=[r['values']['out'] for r in no['rows']]; iv=[r['values']['in'] for r in no['rows']]
    integrate={}
    for stop in (10e9,20e9,50e9,100e9,200e9):
        select=[j for j,v in enumerate(nf) if v<=stop]
        xs=[nf[j] for j in select]
        integrate[str(int(stop))]={'output_integrated_div_midband_gain_vrms':math.sqrt(trap(xs,[ov[j]**2 for j in select]))/gain,
                                  'frequencywise_input_integrated_vrms':math.sqrt(trap(xs,[iv[j]**2 for j in select]))}
    dc=parse_scalar(os.path.join(run,'psf','dcOp.dc'))
    vals=dc.get('values',{})
    return {'gain_db_at_100mhz':20*math.log10(gain),'bandwidth_hz':bw,
            'upper_3db_bandwidth_from_peak_hz':peak_bw,'peak_frequency_hz':f[peak_i],
            'peak_gain_db_relative_100mhz':20*math.log10(max(mag)/gain),'noise':integrate,'dc_raw':vals}

def main():
    p=argparse.ArgumentParser();p.add_argument('config');p.add_argument('run_root');a=p.parse_args()
    c=json.load(open(a.config)); text=make_netlist(c)
    stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%S_%fZ')
    run=os.path.join(a.run_root,stamp+'_'+c['name']);os.makedirs(run)
    open(os.path.join(run,'input.scs'),'w').write(text)
    json.dump(c,open(os.path.join(run,'config.json'),'w'),indent=2,sort_keys=True)
    meta={'input_sha256':hashlib.sha256(text.encode()).hexdigest(),'run_dir':run,'started_utc':stamp}
    cmd=['spectre','input.scs','-format','psfascii','-raw','psf','+log','spectre.log']
    with open(os.path.join(run,'stdout.log'),'w') as f:
        proc=subprocess.Popen(cmd,cwd=run,stdout=f,stderr=subprocess.STDOUT);meta['pid']=proc.pid
        json.dump(meta,open(os.path.join(run,'provenance.json'),'w'),indent=2)
        code=proc.wait()
    meta['exit_code']=code;json.dump(meta,open(os.path.join(run,'provenance.json'),'w'),indent=2)
    if code:
        print(open(os.path.join(run,'stdout.log')).read()[-5000:]);sys.exit(code)
    if c.get('mode','ac')=='tran':
        import glob
        traces=glob.glob(os.path.join(run,'psf','tran*.tran'))
        if len(traces)!=1:raise ValueError('Expected one completed transient PSF file')
        result={'transient_raw':traces[0]}
    elif c.get('mode')=='dc':result={'dc_raw':parse_scalar(os.path.join(run,'psf','dcOp.dc'))['values']}
    else:result=measure(run,c)
    result['run_dir']=run;result['config']=c
    json.dump(result,open(os.path.join(run,'metrics.json'),'w'),indent=2,sort_keys=True)
    print(json.dumps(result,sort_keys=True));sys.stdout.flush()
if __name__=='__main__':main()
