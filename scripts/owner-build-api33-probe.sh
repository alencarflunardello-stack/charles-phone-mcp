#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ "${CODESPACES:-}" == true && -t 0 ]] || { echo "Use o terminal interativo do Codespace original."; exit 1; }
cd /workspaces/charles-phone-mcp
BASE=325bedd75439d33bf7431ae09c996a2670671d8f
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
git show "$BASE:scripts/owner-build-local-tls.sh" > "$TMP/base.sh"
cat > "$TMP/Probe.java" <<'JAVA'
package fr.phonemcp;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.hardware.display.*;
import android.media.*;
import android.os.*;
import android.view.*;
import java.nio.ByteBuffer;
/** Local synthetic diagnostic only, no remote endpoint or input. */
final class Api33DisplayProbe {
 interface Result { void done(String message); }
 private final Activity owner;
 private final Result result;
 private final Handler main=new Handler(Looper.getMainLooper());
 private ImageReader reader;
 private VirtualDisplay virtual;
 private Presentation presentation;
 private int id=-1;
 private boolean finished,receiverRegistered,lifecycleRegistered;
 private final Runnable timeout=()->finish("Inconclusivo: quadro sintético não confirmado.");
 private final BroadcastReceiver screenOff=new BroadcastReceiver(){
  @Override public void onReceive(Context c,Intent i){finish("Interrompido: painel apagado.");}
 };
 private final Application.ActivityLifecycleCallbacks lifecycle=new Application.ActivityLifecycleCallbacks(){
  public void onActivityCreated(Activity a,Bundle b){}
  public void onActivityStarted(Activity a){}
  public void onActivityResumed(Activity a){}
  public void onActivityPaused(Activity a){if(a==owner)finish("Interrompido: atividade pausada.");}
  public void onActivityStopped(Activity a){if(a==owner)finish("Interrompido: atividade parada.");}
  public void onActivitySaveInstanceState(Activity a,Bundle b){}
  public void onActivityDestroyed(Activity a){if(a==owner)finish("Interrompido: atividade encerrada.");}
 };
 private Api33DisplayProbe(Activity a,Result r){owner=a;result=r;}
 static void start(Activity a,Result r){if(Looper.myLooper()!=Looper.getMainLooper())throw new IllegalStateException("Main thread required");new Api33DisplayProbe(a,r).begin();}
 private boolean safe(){return !owner.isFinishing()&&!owner.isDestroyed()&&owner.getDisplay()!=null&&owner.getDisplay().getDisplayId()==Display.DEFAULT_DISPLAY&&owner.getSystemService(PowerManager.class).isInteractive()&&!owner.getSystemService(KeyguardManager.class).isKeyguardLocked();}
 private void begin(){
  try{
   if(Build.VERSION.SDK_INT!=33||!safe()||!owner.hasWindowFocus()||BridgeService.active()){finish("Teste exige Android 13, aparelho desbloqueado e sessão MCP encerrada.");return;}
   if(!owner.getPackageManager().hasSystemFeature(PackageManager.FEATURE_ACTIVITIES_ON_SECONDARY_DISPLAYS)){finish("Sem suporte declarado a displays secundários.");return;}
   owner.registerReceiver(screenOff,new IntentFilter(Intent.ACTION_SCREEN_OFF),Context.RECEIVER_NOT_EXPORTED);receiverRegistered=true;
   owner.getApplication().registerActivityLifecycleCallbacks(lifecycle);lifecycleRegistered=true;
   reader=ImageReader.newInstance(320,240,PixelFormat.RGBA_8888,2);
   reader.setOnImageAvailableListener(this::frame,main);
   virtual=owner.getSystemService(DisplayManager.class).createVirtualDisplay("Charles API 33 local probe",320,240,160,reader.getSurface(),DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION|DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY);
   if(virtual==null||virtual.getDisplay()==null){finish("Falha: display não criado.");return;}
   Display d=virtual.getDisplay();id=d.getDisplayId();
   if(id<=0||!d.isValid()||(d.getFlags()&Display.FLAG_PRIVATE)==0){finish("Falha: display privado distinto do principal não confirmado.");return;}
   presentation=new Presentation(owner,d);
   View marker=new View(presentation.getContext());marker.setBackgroundColor(Color.rgb(39,168,117));presentation.setContentView(marker);presentation.show();
   main.postDelayed(timeout,8000);
  }catch(Exception e){finish("Falha local: "+e.getClass().getSimpleName());}
 }
 private void frame(ImageReader source){
  if(finished)return;
  boolean matched=false;
  try(Image image=source.acquireLatestImage()){
   if(image==null)return;
   if(!safe()||BridgeService.active()||virtual==null||!virtual.getDisplay().isValid()){main.post(()->finish("Interrompido: condição local alterada."));return;}
   Image.Plane p=image.getPlanes()[0];ByteBuffer b=p.getBuffer();
   int i=b.position()+120*p.getRowStride()+160*p.getPixelStride();
   matched=p.getPixelStride()>=4&&i>=0&&i+2<b.limit()&&near(b.get(i),39)&&near(b.get(i+1),168)&&near(b.get(i+2),117);
  }catch(Exception e){main.post(()->finish("Falha de quadro: "+e.getClass().getSimpleName()));return;}
  if(matched)main.post(()->finish("Display privado "+id+" e quadro sintético confirmados. Controle, foco e apps externos não testados."));
 }
 private static boolean near(byte b,int v){return Math.abs((b&255)-v)<=12;}
 private void finish(String s){
  if(finished)return;finished=true;main.removeCallbacks(timeout);
  if(reader!=null)try{reader.setOnImageAvailableListener(null,null);}catch(Exception ignored){}
  if(presentation!=null)try{presentation.dismiss();}catch(Exception ignored){}
  if(virtual!=null)try{virtual.release();}catch(Exception ignored){}
  if(reader!=null)try{reader.close();}catch(Exception ignored){}
  if(receiverRegistered)try{owner.unregisterReceiver(screenOff);}catch(Exception ignored){}
  if(lifecycleRegistered)owner.getApplication().unregisterActivityLifecycleCallbacks(lifecycle);
  result.done(s);
 }
}
JAVA
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=(p/'base.sh').read_text();probe=(p/'Probe.java').read_text()
def change(a,b):
 global s
 if s.count(a)!=1: raise SystemExit('Base divergente: '+a)
 s=s.replace(a,b)
change('VERSION=0.19.1-tablet.2','VERSION=0.19.1-tablet.3')
change('CODE=72','CODE=73')
change('replace("versionCode 71", "versionCode 72")','replace("versionCode 71", "versionCode 73")')
change('"versionName \'0.19.1-tablet.2\'"','"versionName \'0.19.1-tablet.3\'"')
marker='(cd "$work/source" && python3 scripts/prepare-charles-pilot.py'
insert="""cat > "$work/source/android/app/src/main/java/fr/phonemcp/Api33DisplayProbe.java" <<'PROBE_SOURCE'
"""+probe+"""PROBE_SOURCE
python3 - "$work/source" <<'PATCH_ACTIVITY'
from pathlib import Path
import sys
p=Path(sys.argv[1])/"android/app/src/main/java/fr/phonemcp/MainActivity.java"
s=p.read_text()
needle='        LinearLayout updates=card(body);'
assert s.count(needle)==1
extra='        if(Build.VERSION.SDK_INT==33){LinearLayout diagnostic=card(body);text(diagnostic,"Diagnóstico local Android 13",15,TEXT,true);text(diagnostic,"Teste sintético de display privado. Encerre a sessão MCP antes.",12,MUTED,false);button(diagnostic,"Testar display virtual",CARD,ACCENT,()->{if(BridgeService.active()){toast("Encerre a sessão MCP antes do teste.");return;}Api33DisplayProbe.start(this,result->{if(!isFinishing()&&!isDestroyed())new AlertDialog.Builder(this).setTitle("Diagnóstico Android 13").setMessage(result).setPositiveButton("OK",null).show();});});}'
p.write_text(s.replace(needle,extra+chr(10)+needle))
PATCH_ACTIVITY

"""
change(marker,insert+marker)
change('# This is a foreground-only candidate, not an API 33 parallel-mode release.','# Local diagnostic only, not an API 33 parallel-mode release.')
change('Teste somente depois do pareamento local. Nao altere servidor ou OAuth.','Teste local em Configuracoes > Testar display virtual com sessao MCP encerrada. Nao altere servidor ou OAuth.')
(p/'build.sh').write_text(s)
PY
bash -n "$TMP/build.sh"
bash "$TMP/build.sh"
