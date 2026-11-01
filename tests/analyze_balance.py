"""Summarise tests/balance.gd output. Usage: python3 tests/analyze_balance.py out_*.log"""
import json, glob, math, sys
files = sys.argv[1:] or glob.glob('out_*.log')
rows=[json.loads(l[10:]) for f in files for l in open(f) if l.startswith('[BALANCE] ')]
MAPS={0:'Iron Bridge (pitched)',1:'Bastion Redoubt (player defends)',2:'Kessel-9 (player assaults)'}
V=['full','none_both','none_player','none_ai','no_combat','no_patch','double_both','double_player','no_upkeep','no_city_heal','no_city_heal_ai']
idx={(r['variant'],r['map'],r['policy']):r for r in rows}
has_full=lambda m,p: ('full',m,p) in idx
def ci(w,n):
    p=w/n; h=1.96*math.sqrt(p*(1-p)/n); return f"{100*p:3.0f}% ±{100*h:2.0f}"
print("== Player win rate (games per row shown) | flips vs full (P->AI / AI->P) | avg turns | end state P alive/hp vs AI alive/hp ==")
for m in range(3):
    print(f"\n{MAPS[m]}")
    for v in V:
        rs=[r for r in rows if r['map']==m and r['variant']==v]
        if not rs: continue
        n=len(rs); w=sum(r['winner']=='PLAYER' for r in rs)
        pa=sum(1 for r in rs if has_full(m,r['policy']) and idx[('full',m,r['policy'])]['winner']=='PLAYER' and r['winner']=='AI')
        ap=sum(1 for r in rs if has_full(m,r['policy']) and idx[('full',m,r['policy'])]['winner']=='AI' and r['winner']=='PLAYER')
        av=lambda k: sum(r[k] for r in rs)/n
        print(f"  {v:15s} {w:2d}/{n} {ci(w,n)}  flips {pa:2d}/{ap:2d}  turns {av('turns'):4.1f}  P {av('p_alive'):.1f}/{av('p_hp'):4.0f}  AI {av('a_alive'):.1f}/{av('a_hp'):4.0f}")
print("\n== How games end (full) ==")
for m in range(3):
    rs=[r for r in rows if r['map']==m and r['variant']=='full']
    c={}
    for r in rs: c[r['reason']]=c.get(r['reason'],0)+1
    print(f"  {MAPS[m]}: {c}")
print("\n== Entrench + City healing usage (full, totals over all games) ==")
for m in range(3):
    rs=[r for r in rows if r['map']==m and r['variant']=='full']
    t=lambda k,i: sum(r[k][i] for r in rs)
    print(f"  {MAPS[m]:34s} entrench P/AI {t('entrench',0)}/{t('entrench',1)}  +8 patch P/AI {t('patch_heal',0)}/{t('patch_heal',1)}  +12 upkeep P/AI {t('upkeep_heal',0)}/{t('upkeep_heal',1)}")
print("\n== Fights (full): attacker side, live win %, live dmg dealt/taken, entrenched defenders (forecast with vs without entrenchment) ==")
for m in range(3):
    sk=[s for r in rows if r['map']==m and r['variant']=='full' for s in r['skirmishes']]
    for fac,name in ((0,'AI attacks'),(1,'Player attacks')):
        ss=[s for s in sk if s['def_faction']==fac]
        if not ss: continue
        n=len(ss); es=[s for s in ss if s['entrenched']]
        line=f"  {MAPS[m]:34s} {name:15s} n={n:3d} atk win {sum(s['atk_won'] for s in ss)/n:.0%} dmg {sum(s['dmg_def'] for s in ss)/n:3.0f}/{sum(s['dmg_atk'] for s in ss)/n:3.0f}  vs entrenched {len(es)}"
        if es:
            k=len(es)
            line+=f" -> dmg taken cut {sum(s['cf_dmg_def']-s['fc_dmg_def'] for s in es)/k:.0f} of {sum(s['cf_dmg_def'] for s in es)/k:.0f}, counter +{sum(s['fc_dmg_atk']-s['cf_dmg_atk'] for s in es)/k:.0f}, clashes flipped {sum(s['cf_atk_won'] and not s['fc_atk_won'] for s in es)}, defenders saved {sum(s['cf_def_dead'] and not s['fc_def_dead'] for s in es)}, attackers killed {sum(s['fc_atk_dead'] and not s['cf_atk_dead'] for s in es)}"
        print(line)
