import subprocess,json,time,pathlib,re
log=pathlib.Path.home()/'Library/Logs/LeanKeys/debug.log'
for interval in [100,50,33]:
 start=log.stat().st_size
 cmds=[{'command':'press','args':{'combo':'cmd+a'}},{'command':'press','args':{'combo':'backspace'}}]
 for k in 'chaof banj '*2:
  cmds += [{'command':'press','args':{'combo':'space' if k==' ' else k}},{'command':'wait','args':{'ms':interval}}]
 r=json.loads(subprocess.check_output(['agent-desktop','--headed','batch',json.dumps(cmds),'--stop-on-error']))
 assert r['ok'],r
 v=json.loads(subprocess.check_output(['agent-desktop','get','@s1a5cxahmjsgpt:e27','--property','value']))['data']['value']
 with log.open() as f:f.seek(start);s=f.read()
 out={'interval_ms':interval,'output':v,'correct':v=='Chào bạn chào bạn '}
 for label,pattern in [('key','perf: key ms=([0-9.]+)'),('send','perf: send .*? ms=([0-9.]+)')]:
  a=sorted(map(float,re.findall(pattern,s)));out[label]={'n':len(a),'p50':a[len(a)//2],'p95':a[int(len(a)*.95)],'max':a[-1]} if a else None
 pathlib.Path(f'/tmp/leankeys-audit-v2/live-{interval}.json').write_text(json.dumps(out));print(out,flush=True)
