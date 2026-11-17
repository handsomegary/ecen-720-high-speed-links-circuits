from __future__ import print_function
import copy,datetime,glob,json,os,re,subprocess,sys
from la_sim import make_netlist,measure
from parse_psf import parse_scalar
root=os.path.dirname(os.path.abspath(__file__));project=os.path.dirname(root)
base=json.load(open(os.path.join(project,'configs',sys.argv[1]+'.json')))
# Exact matched common mode from the already simulated nominal candidate.
matches=glob.glob(os.path.join(project,'runs','*_'+base['name'],'metrics.json'))
dc=json.load(open(matches[-1]))['dc_raw'];base['input_cm_v']=(dc['outp']+dc['outn'])/2
checks=[]
for offset in (-.005,0,.005):
 for servo in (False,True):
  c=copy.deepcopy(base);c.update(mode='dc',offset_v=offset,servo=servo)
  c['name']='offset_%s_%s'%('on' if servo else 'off',str(offset));checks.append(c)
for label,offset,servo,noisy in (('nominal',0,True,False),('offset_corrected',.005,True,False),('offset_uncorrected',.005,False,False),('device_noise',0,True,True)):
 c=copy.deepcopy(base);c.update(mode='tran',bits=1024 if noisy else 2048,input_vppd=.01,offset_v=offset,servo=servo,transient_noise=noisy)
 c['name']='eye_'+label;checks.append(c)
for c in checks:
 path=os.path.join(project,'configs',c['name']+'.json');json.dump(c,open(path,'w'),indent=2)
 code=subprocess.call([sys.executable,os.path.join(root,'la_sim.py'),path,os.path.join(project,'runs')])
 if code:sys.exit(code)
for on in (False,True):
 c=copy.deepcopy(base);c.update(mode='dc',servo=on,section='top_localmc',model_file=os.path.join(root,'la5_foundry_corners.scs'))
 text=make_netlist(c)
 # Wrap only the DC analysis. Same transistor instance names/order and seed.
 text=text.replace('dcOp dc write="spectre.dc"', 'mc montecarlo numruns=32 seed=7312026 variations=mismatch savefamilyplots=yes {\ndcOp dc\n}')
 text=re.sub(r'(?m)^dcOpInfo info[^\n]*','',text)
 stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%S_%fZ')
 run=os.path.join(project,'runs',stamp+'_mc_offset_'+('on' if on else 'off'));os.makedirs(run)
 open(os.path.join(run,'input.scs'),'w').write(text);json.dump(c,open(os.path.join(run,'config.json'),'w'),indent=2)
 with open(os.path.join(run,'stdout.log'),'w') as f:
  code=subprocess.call(['spectre','input.scs','-format','psfascii','-raw','psf','+log','spectre.log'],cwd=run,stdout=f,stderr=subprocess.STDOUT)
 if code:print(open(os.path.join(run,'stdout.log')).read()[-3000:]);sys.exit(code)
 results=[]
 for f in glob.glob(run+'/psf/**/*dcOp*',recursive=True):
  if not os.path.isfile(f):continue
  try:
   vals=parse_scalar(f)['values']
   if 'outp' in vals and 'outn' in vals:results.append({'file':f,'offset_v':vals['outp']-vals['outn']})
  except Exception:pass
 json.dump({'run_dir':run,'servo':on,'samples':results,'exit_code':code},open(os.path.join(run,'mc_metrics.json'),'w'),indent=2)
 print('MC_COMPLETED '+run+' SAMPLES='+str(len(results)));sys.stdout.flush()
