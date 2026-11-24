package br.charles.hoverprobe;

import android.os.IBinder;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.lang.reflect.Method;

/** Diagnostic only. Requires the authorized shell uid and explicit non-primary display.
 * A single unpressed mouse event, targeted to one UID; never falls back to global injection.
 * The caller must verify an owned isolated window, bounds and unprotected UI before execution.
 */
public final class HoverProbe {
  public static void main(String[] args) throws Exception {
    if (args.length != 6 || android.os.Process.myUid() != 2000) throw new SecurityException("Expected authorized shell and six arguments");
    int display=Integer.parseInt(args[0]), uid=Integer.parseInt(args[1]), x=Integer.parseInt(args[2]), y=Integer.parseInt(args[3]), width=Integer.parseInt(args[4]), height=Integer.parseInt(args[5]);
    if(display<=0||uid<10000||width<1||height<1||width>8192||height>8192||x<0||y<0||x>=width||y>=height)throw new SecurityException("Invalid isolated target");
    MotionEvent.PointerProperties prop=new MotionEvent.PointerProperties();prop.id=0;prop.toolType=MotionEvent.TOOL_TYPE_MOUSE;
    MotionEvent.PointerCoords coord=new MotionEvent.PointerCoords();coord.x=x;coord.y=y;coord.pressure=0;coord.size=0;
    long now=SystemClock.uptimeMillis();
    MotionEvent ev=MotionEvent.obtain(now,now,MotionEvent.ACTION_HOVER_MOVE,1,new MotionEvent.PointerProperties[]{prop},new MotionEvent.PointerCoords[]{coord},0,0,1,1,0,0,InputDevice.SOURCE_MOUSE,0);
    try{
      InputEvent.class.getMethod("setDisplayId",int.class).invoke(ev,display);
      if((Integer)InputEvent.class.getMethod("getDisplayId").invoke(ev)!=display)throw new SecurityException("Display mismatch");
      IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"input");
      Object input=Class.forName("android.hardware.input.IInputManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
      Method inject=Class.forName("android.hardware.input.IInputManager").getMethod("injectInputEventToTarget",InputEvent.class,int.class,int.class);
      if(!Boolean.TRUE.equals(inject.invoke(input,ev,2,uid)))throw new IllegalStateException("Hover refused by Android; do not replay");
      System.out.println("HOVER_DELIVERED display="+display+" action=HOVER_MOVE buttons=0");
    }finally{ev.recycle();}
  }
}
