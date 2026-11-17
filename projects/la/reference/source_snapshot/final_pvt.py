from __future__ import print_function
import copy,json,os,subprocess,sys
root=os.path.dirname(os.path.abspath(__file__));project=os.path.dirname(root)
base=json.load(open(os.path.join(project,'configs','r1_rl260_rt20_tt_t27.json')))
for corner in ('tt','ff','ss'):
 for temp in (-40,27,85):
  if (corner,temp) in (('tt',27),('ff',85),('ss',-40)):continue
  c=copy.deepcopy(base);c['temperature_c']=temp
  if corner!='tt':c.update(model_file=os.path.join(root,'la5_foundry_corners.scs'),section='top_'+corner)
  c['name']='final_pvt_'+corner+'_t'+str(temp)
  path=os.path.join(project,'configs',c['name']+'.json');json.dump(c,open(path,'w'),indent=2)
  code=subprocess.call([sys.executable,os.path.join(root,'la_sim.py'),path,os.path.join(project,'runs')])
  if code:sys.exit(code)
