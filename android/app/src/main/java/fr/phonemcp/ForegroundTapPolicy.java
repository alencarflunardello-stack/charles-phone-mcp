package fr.phonemcp;

import java.util.List;

/** Conservative foreground batch: only a unique observed native button, never canvas or blind coordinates. */
final class ForegroundTapPolicy {
    static final class Target {
        final String id,identity;
        final int left,top,right,bottom;
        Target(String id,String identity,int l,int t,int r,int b){this.id=id;this.identity=identity;left=l;top=t;right=r;bottom=b;}
        boolean contains(int x,int y){return x>=left&&x<right&&y>=top&&y<bottom;}
        boolean same(Target other){return other!=null&&id.equals(other.id)&&identity.equals(other.identity)&&left==other.left&&top==other.top&&right==other.right&&bottom==other.bottom;}
    }
    static Target unique(List<Target> targets,int x,int y){
        Target found=null;
        for(Target target:targets)if(target.contains(x,y)){
            if(found!=null)throw new IllegalArgumentException("Ambiguous native tap target.");
            found=target;
        }
        if(found==null)throw new IllegalArgumentException("Only observed native buttons are supported in foreground sequences.");
        return found;
    }
    static boolean bounds(int count,int interval,int timeout){
        return count>=1&&count<=8&&interval>=0&&interval<=250&&timeout>=500&&timeout<=8000&&count*80L+(count-1L)*interval<=timeout;
    }
}
