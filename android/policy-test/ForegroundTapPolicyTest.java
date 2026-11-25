package fr.phonemcp;
import java.util.Arrays;
import java.util.Collections;
public final class ForegroundTapPolicyTest {
    static int checks;
    static void expect(boolean value){checks++;if(!value)throw new AssertionError("foreground tap policy");}
    static void reject(Runnable r){checks++;try{r.run();}catch(IllegalArgumentException expected){return;}throw new AssertionError("unsafe target accepted");}
    public static void main(String[] args){
        ForegroundTapPolicy.Target a=new ForegroundTapPolicy.Target("0.1","buttonA",10,10,100,100);
        ForegroundTapPolicy.Target b=new ForegroundTapPolicy.Target("0.2","buttonB",100,10,200,100);
        expect(ForegroundTapPolicy.unique(Arrays.asList(a,b),99,99)==a);
        expect(ForegroundTapPolicy.unique(Arrays.asList(a,b),100,99)==b);
        reject(()->ForegroundTapPolicy.unique(Collections.singletonList(a),100,100));
        reject(()->ForegroundTapPolicy.unique(Arrays.asList(a,a),20,20));
        expect(a.same(new ForegroundTapPolicy.Target("0.1","buttonA",10,10,100,100)));
        expect(!a.same(new ForegroundTapPolicy.Target("0.1","changed",10,10,100,100)));
        expect(!a.same(new ForegroundTapPolicy.Target("0.1","buttonA",11,10,100,100)));
        expect(!a.same(b));
        expect(ForegroundTapPolicy.bounds(4,100,4000));
        expect(!ForegroundTapPolicy.bounds(9,0,4000));
        expect(!ForegroundTapPolicy.bounds(0,0,4000));
        expect(!ForegroundTapPolicy.bounds(8,250,500));
        expect(!ForegroundTapPolicy.bounds(1,251,4000));
        expect(!ForegroundTapPolicy.bounds(1,0,8001));
        System.out.println("PASS: "+checks+" foreground tap policy checks");
    }
}
