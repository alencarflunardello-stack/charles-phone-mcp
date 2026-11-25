package fr.phonemcp;

public final class FeatureCompatibilityTest {
    private static void expect(boolean b){if(!b)throw new AssertionError("Unexpected SDK eligibility");}
    public static void main(String[] args){
        expect(!FeatureCompatibility.canStart(true,30));
        expect(!FeatureCompatibility.canStart(true,33));
        expect(FeatureCompatibility.canStart(true,34));
        expect(FeatureCompatibility.canStart(true,36));
        expect(FeatureCompatibility.canStart(false,33));
        expect(FeatureCompatibility.canStart(false,30));
        expect(!FeatureCompatibility.canStart(false,29));
        System.out.println("PASS: 7 feature SDK eligibility checks (not real-device isolation)");
    }
}
