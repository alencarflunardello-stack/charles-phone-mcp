package fr.phonemcp;

import android.os.Binder;
import android.os.IBinder;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/** Shell-only, UID-targeted input. No wake, global focus mutation, retry or display fallback. */
@android.annotation.SuppressLint({"PrivateApi","DiscouragedPrivateApi"})
final class NativeGestureInjector {
    interface Guard {void check() throws Exception;}
    static void dispatch(List<TouchGestures.Stroke> paths,int display,int uid,int width,int height,Guard guard)throws Exception{
        if(android.os.Process.myUid()!=2000||display<=0||uid<0)throw new SecurityException("Affichage ou UID tactile invalide.");
        requireInteractive(display);
        List<NativeGesturePolicy.Stroke> strokes=new ArrayList<>();
        for(TouchGestures.Stroke p:paths)strokes.add(new NativeGesturePolicy.Stroke(p.x,p.y,p.toX,p.toY,p.start,p.duration));
        List<NativeGesturePolicy.Event> events=NativeGesturePolicy.timeline(strokes,width,height);
        IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"input");
        Object input=Class.forName("android.hardware.input.IInputManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
        Method inject=Class.forName("android.hardware.input.IInputManager").getMethod("injectInputEventToTarget",InputEvent.class,int.class,int.class);
        long origin=SystemClock.uptimeMillis();NativeGesturePolicy.Event last=null;boolean complete=false,attempted=false;
        try{
            for(NativeGesturePolicy.Event event:events){
                guard.check();requireInteractive(display);long wait=origin+event.at-SystemClock.uptimeMillis();if(wait>0)Thread.sleep(wait);guard.check();
                MotionEvent motion=motion(event,origin,display);last=event;attempted=true;
                boolean delivered;
                long identity=Binder.clearCallingIdentity();
                try{delivered=Boolean.TRUE.equals(inject.invoke(input,motion,2,uid));}
                catch(InvocationTargetException failure){Throwable cause=failure.getCause();if(cause instanceof Exception)throw (Exception)cause;throw failure;}
                finally{Binder.restoreCallingIdentity(identity);motion.recycle();}
                if(!delivered)throw new IllegalStateException("Android n'a pas confirmé la livraison du geste à l'application sur son écran IA. Aucun geste n'est rejoué. Relisez l'état.");
                guard.check();requireInteractive(display);
            }
            complete=true;
        }finally{
            if(!complete&&attempted&&last!=null){
                NativeGesturePolicy.Event canceled=new NativeGesturePolicy.Event(last.at,last.downAt,NativeGesturePolicy.CANCEL,last.xs,last.ys);
                MotionEvent motion=motion(canceled,origin,display);long identity=Binder.clearCallingIdentity();
                try{inject.invoke(input,motion,0,uid);}catch(Exception ignored){}finally{Binder.restoreCallingIdentity(identity);motion.recycle();}
            }
        }
    }
    /** Mouse hover only: no button, no click, no drag, no physical display fallback. */
    static void hover(int x,int y,int display,int uid,int width,int height,Guard guard)throws Exception{
        if(android.os.Process.myUid()!=2000||display<=0||uid<0||x<0||y<0||x>=width||y>=height)
            throw new SecurityException("Invalid mouse hover target.");
        guard.check();requireInteractive(display);
        MotionEvent.PointerProperties property=new MotionEvent.PointerProperties();
        property.id=0;property.toolType=MotionEvent.TOOL_TYPE_MOUSE;
        MotionEvent.PointerCoords coordinate=new MotionEvent.PointerCoords();
        coordinate.x=x;coordinate.y=y;coordinate.pressure=0;coordinate.size=0;
        long now=SystemClock.uptimeMillis();
        MotionEvent motion=MotionEvent.obtain(now,now,MotionEvent.ACTION_HOVER_MOVE,1,
            new MotionEvent.PointerProperties[]{property},new MotionEvent.PointerCoords[]{coordinate},
            0,0,1,1,0,0,InputDevice.SOURCE_MOUSE,0);
        try{
            InputEvent.class.getMethod("setDisplayId",int.class).invoke(motion,display);
            if((Integer)InputEvent.class.getMethod("getDisplayId").invoke(motion)!=display)
                throw new SecurityException("Mouse event display mismatch.");
            IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"input");
            Object input=Class.forName("android.hardware.input.IInputManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
            Method inject=Class.forName("android.hardware.input.IInputManager").getMethod("injectInputEventToTarget",InputEvent.class,int.class,int.class);
            guard.check();requireInteractive(display);
            boolean delivered;
            long identity=Binder.clearCallingIdentity();
            try{delivered=Boolean.TRUE.equals(inject.invoke(input,motion,2,uid));}
            catch(InvocationTargetException failure){Throwable cause=failure.getCause();if(cause instanceof Exception)throw (Exception)cause;throw failure;}
            finally{Binder.restoreCallingIdentity(identity);}
            if(!delivered)throw new IllegalStateException("Android refused target-UID mouse hover. Observe again; do not replay automatically.");
            guard.check();requireInteractive(display);
        }finally{motion.recycle();}
    }
    private static void requireInteractive(int display)throws Exception{
        IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"power");
        Object power=Class.forName("android.os.IPowerManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
        Object interactive=Class.forName("android.os.IPowerManager").getMethod("isDisplayInteractive",int.class).invoke(power,display);
        if(!Boolean.TRUE.equals(interactive))throw new IllegalStateException("L’écran IA est non interactif selon Android. Le geste est refusé : le système peut annoncer un succès sans le transmettre en veille. Aucun réveil de l’écran physique et aucune répétition automatique ne sont effectués.");
    }
    private static MotionEvent motion(NativeGesturePolicy.Event event,long origin,int display)throws Exception{
        int count=event.xs.length;MotionEvent.PointerProperties[] props=new MotionEvent.PointerProperties[count];MotionEvent.PointerCoords[] coords=new MotionEvent.PointerCoords[count];
        for(int i=0;i<count;i++){props[i]=new MotionEvent.PointerProperties();props[i].id=i;props[i].toolType=MotionEvent.TOOL_TYPE_FINGER;coords[i]=new MotionEvent.PointerCoords();coords[i].x=event.xs[i];coords[i].y=event.ys[i];coords[i].pressure=event.action==NativeGesturePolicy.UP?0:1;coords[i].size=1;}
        MotionEvent motion=MotionEvent.obtain(origin+event.downAt,SystemClock.uptimeMillis(),event.action,count,props,coords,0,0,1,1,0,0,InputDevice.SOURCE_TOUCHSCREEN,0);
        InputEvent.class.getMethod("setDisplayId",int.class).invoke(motion,display);
        if((Integer)InputEvent.class.getMethod("getDisplayId").invoke(motion)!=display){motion.recycle();throw new SecurityException("Cible tactile incohérente.");}
        return motion;
    }
}
