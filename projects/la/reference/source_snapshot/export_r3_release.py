import csv,glob,json,os,shutil,sys,math
from parse_psf import parse_sweep
from fast_total_noise import parse_total_noise
project=os.path.dirname(os.path.dirname(os.path.abspath(__file__)));release=project+'/release_r3_pvt_correction'
for name in ['r3_grid_final44_summary.json','r3_grid_passive40_summary.json','r3_grid_fast_summary.json','r3_gate_sensitivity_summary.json','r3_active_summary.json','r3_fine_summary.json','r3_passive12_summary.json']:
 if os.path.exists(project+'/'+name):shutil.copy2(project+'/'+name,release+'/data/'+name)
shutil.copy2(project+'/configs/r3_selected_final44.json',release+'/data/r3_selected.json')
a=json.load(open(project+'/r3_grid_final44_summary.json'))
cols=['corner','temperature_c','vdd_v','gain_db_100mhz','upper_3db_bw_ghz','peak_db','noise_1k_20g_mvrms','dc_power_mw','passes_specs','run_dir']
with open(release+'/data/pvt.csv','w') as f:
 w=csv.writer(f);w.writerow(cols)
 for d in a:
  c=d['config'];w.writerow([c['section'],c['temperature_c'],c['vdd'],d['gain_db_at_100mhz'],d['upper_3db_bandwidth_from_peak_hz']/1e9,d['peak_gain_db_relative_100mhz'],d['noise20_exact_vrms']*1e3,d['dc_power_mw'],d['passes_specs'],d['run_dir']])
selected=[d for d in a if d['config']['section']=='tt' and d['config']['temperature_c']==27 and d['config']['vdd']==.9]
if len(a)==27:
 selected+=[min(a,key=lambda d:d['upper_3db_bandwidth_from_peak_hz']),min(a,key=lambda d:d['gain_db_at_100mhz'])]
for index,d in enumerate(selected):
 label=['nominal','worst_bw','worst_gain'][index];p=d['run_dir']
 shutil.copy2(p+'/input.scs',release+'/netlists/'+label+'.scs')
 for name in ['config.json','provenance.json','spectre.log']:shutil.copy2(p+'/'+name,release+'/netlists/'+label+'_'+name)
 ac=parse_sweep(p+'/psf/ac.ac',required_signals=['outp','outn'])
 no=parse_total_noise(p+'/psf/noise.noise')
 with open(release+'/waveforms/ac_'+label+'.csv','w') as f:
  w=csv.writer(f);w.writerow(['frequency_hz','gain_db','phase_rad'])
  for r in ac['rows']:
   h=complex(*r['values']['outp'])-complex(*r['values']['outn']);w.writerow([r['axis_value'],20*math.log10(abs(h)),math.atan2(h.imag,h.real)])
 with open(release+'/waveforms/noise_'+label+'.csv','w') as f:
  w=csv.writer(f);w.writerow(['frequency_hz','input_asd_v_sqrthz','output_asd_v_sqrthz'])
  for r in no['rows']:w.writerow([r['axis_value'],r['values']['in'],r['values']['out']])
print('R3_METADATA_EXPORT',len(a),'cases',len(selected),'response_traces')
