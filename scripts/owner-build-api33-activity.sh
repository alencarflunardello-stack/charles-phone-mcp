#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /workspaces/charles-phone-mcp
export CHARLES_LOCAL_TLS_SHA256=a39fe7663e39fcbf0e527df5d32594dc7f07949b5859844f625d89c21bcd1a24
apk=$(find /workspaces/charles-owner-private/output -name 'Charles-Phone-MCP-0.19.1-tablet.3.apk' -print -quit)
test -n "$apk"
f=$(mktemp)
trap 'rm -f -- "$f"' EXIT
cat > "$f" <<'CHARLES_PROBE_STAGE_TWO'
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
/** Owner-initiated local activity diagnostic; no external apps, input or remote endpoint. */
public final class Api33DisplayProbe {
 interface Result { void done(String message); }
 private static Api33DisplayProbe active;
 private final Activity owner;
 private final Result result;
 private final Handler main=new Handler(Looper.getMainLooper());
 private ImageReader reader;
 private VirtualDisplay virtual;
 private ProbeActivity target;
 private int id=-1;
 private boolean finished,receiverRegistered,lifecycleRegistered,resumed;
 private final Runnable timeout=()->finish("Inconclusivo: atividade ou quadro nao confirmado.");
 private final BroadcastReceiver screenOff=new BroadcastReceiver(){
  @Override public void onReceive(Context c,Intent i){finish("Interrompido: painel apagado.");}
 };
 private final Application.ActivityLifecycleCallbacks lifecycle=new Application.ActivityLifecycleCallbacks(){
  public void onActivityCreated(Activity a,Bundle b){}
  public void onActivityStarted(Activity a){}
  public void onActivityResumed(Activity a){}
  public void onActivityPaused(Activity a){if(a==owner)finish("Interrompido: atividade principal pausada.");}
  public void onActivityStopped(Activity a){if(a==owner)finish("Interrompido: atividade principal parada.");}
  public void onActivitySaveInstanceState(Activity a,Bundle b){}
  public void onActivityDestroyed(Activity a){if(a==owner)finish("Interrompido: atividade principal encerrada.");}
 };
 private Api33DisplayProbe(Activity a,Result r){owner=a;result=r;}
 static void start(Activity a,Result r){
  if(Looper.myLooper()!=Looper.getMainLooper())throw new IllegalStateException("Main thread required");
  if(active!=null){r.done("Diagnostico ja em andamento.");return;}
  active=new Api33DisplayProbe(a,r);active.begin();
 }
 private boolean safe(){
  return !owner.isFinishing()&&!owner.isDestroyed()&&owner.getDisplay()!=null&&owner.getDisplay().getDisplayId()==Display.DEFAULT_DISPLAY&&owner.getSystemService(PowerManager.class).isInteractive()&&!owner.getSystemService(KeyguardManager.class).isKeyguardLocked()&&!BridgeService.active();
 }
 private boolean validTarget(Activity a){
  return !finished&&active==this&&safe()&&virtual!=null&&virtual.getDisplay()!=null&&virtual.getDisplay().isValid()&&a.getDisplay()!=null&&id>0&&a.getDisplay().getDisplayId()==id&&a.getTaskId()!=owner.getTaskId();
 }
 private void begin(){
  try{
   if(Build.VERSION.SDK_INT!=33||!safe()||!owner.hasWindowFocus()){finish("Teste exige Android 13 desbloqueado e sessao MCP encerrada.");return;}
   if(!owner.getPackageManager().hasSystemFeature(PackageManager.FEATURE_ACTIVITIES_ON_SECONDARY_DISPLAYS)){finish("Sem suporte a displays secundarios.");return;}
   owner.registerReceiver(screenOff,new IntentFilter(Intent.ACTION_SCREEN_OFF),Context.RECEIVER_NOT_EXPORTED);receiverRegistered=true;
   owner.getApplication().registerActivityLifecycleCallbacks(lifecycle);lifecycleRegistered=true;
   reader=ImageReader.newInstance(640,480,PixelFormat.RGBA_8888,2);
   reader.setOnImageAvailableListener(this::frame,main);
   virtual=owner.getSystemService(DisplayManager.class).createVirtualDisplay("Charles API 33 activity probe",640,480,160,reader.getSurface(),DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION|DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY);
   if(virtual==null||virtual.getDisplay()==null){finish("Falha: display nao criado.");return;}
   Display d=virtual.getDisplay();id=d.getDisplayId();
   if(id<=0||!d.isValid()||(d.getFlags()&Display.FLAG_PRIVATE)==0){finish("Falha: display privado distinto nao confirmado.");return;}
   Intent intent=new Intent(owner,ProbeActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
   if(!owner.getSystemService(ActivityManager.class).isActivityStartAllowedOnDisplay(owner,id,intent)){finish("Android negou abertura de Activity no display privado.");return;}
   main.postDelayed(timeout,10000);
   owner.startActivity(intent,ActivityOptions.makeBasic().setLaunchDisplayId(id).toBundle());
  }catch(Exception e){finish("Falha local: "+e.getClass().getSimpleName());}
 }
 public static final class ProbeActivity extends Activity {
  @Override protected void onCreate(Bundle b){
   super.onCreate(b);
   Api33DisplayProbe p=active;
   if(p==null||!p.validTarget(this)){finish();if(p!=null)p.finish("Falha: Activity fora do display ou tarefa esperados.");return;}
   p.target=this;
   View marker=new View(this);marker.setBackgroundColor(Color.rgb(39,168,117));setContentView(marker);
  }
  @Override protected void onResume(){
   super.onResume();Api33DisplayProbe p=active;
   if(p==null||p.target!=this||!p.validTarget(this)){finish();if(p!=null)p.finish("Falha: retomada fora do display esperado.");return;}
   p.resumed=true;
  }
  @Override protected void onPause(){
   Api33DisplayProbe p=active;if(p!=null&&p.target==this){p.resumed=false;p.main.post(()->p.finish("Interrompido: Activity secundaria pausada."));}
   super.onPause();
  }
 }
 private void frame(ImageReader source){
  if(finished)return;
  boolean matched=false;
  try(Image image=source.acquireLatestImage()){
   if(image==null)return;
   if(!safe()||virtual==null||!virtual.getDisplay().isValid()){main.post(()->finish("Interrompido: condicao local alterada."));return;}
   if(target==null||!resumed||!validTarget(target))return;
   Image.Plane p=image.getPlanes()[0];ByteBuffer b=p.getBuffer();
   int i=b.position()+240*p.getRowStride()+320*p.getPixelStride();
   matched=p.getPixelStride()>=4&&i>=0&&i+2<b.limit()&&near(b.get(i),39)&&near(b.get(i+1),168)&&near(b.get(i+2),117);
  }catch(Exception e){main.post(()->finish("Falha de quadro: "+e.getClass().getSimpleName()));return;}
  if(matched)main.post(()->{
   if(!resumed||target==null||!validTarget(target)){finish("Inconclusivo: condicao alterada antes da verificacao.");return;}
   finish("Activity propria retomada e quadro confirmado no display "+id+". Foco principal: "+owner.hasWindowFocus()+". Foco secundario: "+target.hasWindowFocus()+". Entrada e apps externos nao testados.");
  });
 }
 private static boolean near(byte b,int v){return Math.abs((b&255)-v)<=12;}
 private void finish(String s){
  if(finished)return;finished=true;main.removeCallbacks(timeout);if(active==this)active=null;
  if(reader!=null)try{reader.setOnImageAvailableListener(null,null);}catch(Exception ignored){}
  if(target!=null)try{target.finishAndRemoveTask();}catch(Exception ignored){}
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
change('VERSION=0.19.1-tablet.2','VERSION=0.19.1-tablet.4')
change('CODE=72','CODE=74')
change('replace("versionCode 71", "versionCode 72")','replace("versionCode 71", "versionCode 74")')
change('"versionName \'0.19.1-tablet.2\'"','"versionName \'0.19.1-tablet.4\'"')
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
extra='        if(Build.VERSION.SDK_INT==33){LinearLayout diagnostic=card(body);text(diagnostic,"Diagnóstico local Android 13",15,TEXT,true);text(diagnostic,"Teste de Activity própria em display privado. Encerre a sessão MCP antes.",12,MUTED,false);button(diagnostic,"Testar atividade virtual",CARD,ACCENT,()->{if(BridgeService.active()){toast("Encerre a sessão MCP antes do teste.");return;}Api33DisplayProbe.start(this,result->{if(!isFinishing()&&!isDestroyed())new AlertDialog.Builder(this).setTitle("Diagnóstico Android 13").setMessage(result).setPositiveButton("OK",null).show();});});}'
p.write_text(s.replace(needle,extra+chr(10)+needle))
manifest=Path(sys.argv[1])/"android/app/src/main/AndroidManifest.xml"
m=manifest.read_text()
anchor="        <activity android:name=" + chr(34) + ".MainActivity" + chr(34)
assert m.count(anchor)==1
entry='        <activity android:name=".Api33DisplayProbe$ProbeActivity" android:exported="false" android:excludeFromRecents="true" android:taskAffinity="${applicationId}.api33probe" android:resizeableActivity="true" android:theme="@android:style/Theme.Material.Light.NoActionBar" />'
manifest.write_text(m.replace(anchor,entry+chr(10)+anchor))

PATCH_ACTIVITY

"""
change(marker,insert+marker)
change('# This is a foreground-only candidate, not an API 33 parallel-mode release.','# Local diagnostic only, not an API 33 parallel-mode release.')
change('Teste somente depois do pareamento local. Nao altere servidor ou OAuth.','Teste local em Configuracoes > Testar atividade virtual com sessao MCP encerrada. Nao altere servidor ou OAuth.')
(p/'build.sh').write_text(s)
PY
bash -n "$TMP/build.sh"
bash "$TMP/build.sh"
CHARLES_PROBE_STAGE_TWO
CHARLES_LOCAL_TLS_PUBLIC_CERT=$(python3 - "$apk" <<'PY'
import zipfile, hashlib, base64, re, os, sys
expected=os.environ['CHARLES_LOCAL_TLS_SHA256']
with zipfile.ZipFile(sys.argv[1]) as z:
    for e in z.infolist():
        if e.is_dir() or not 256 <= e.file_size <= 65536: continue
        b=z.read(e)
        candidates=[b]
        for m in re.finditer(rb'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----',b,re.S):
            try: candidates.append(base64.b64decode(re.sub(rb'\s+',b'',m[1]),validate=True))
            except ValueError: pass
        for der in candidates:
            if hashlib.sha256(der).hexdigest()==expected:
                print(base64.b64encode(der).decode()); sys.exit(0)
raise SystemExit('Certificado original nao localizado; compilacao cancelada.')
PY
)
test -n "$CHARLES_LOCAL_TLS_PUBLIC_CERT"
export CHARLES_LOCAL_TLS_PUBLIC_CERT
python3 - "$f" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
marker="(p/'build.sh').write_text(s)"
a='read -r -p "Certificado PUBLICO DER em base64 (uma linha): " public_cert'
b='public_cert="${CHARLES_LOCAL_TLS_PUBLIC_CERT:?}"'
assert s.count(marker)==1
p.write_text(s.replace(marker, f'change({a!r},{b!r})\n'+marker))
PY
bash -n "$f"
echo 'Certificado original localizado e conferido.'
bash "$f"
