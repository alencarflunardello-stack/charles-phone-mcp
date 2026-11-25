package fr.phonemcp;

/** SDK eligibility only, not a certificate of runtime isolation. */
final class FeatureCompatibility {
    static boolean canStart(boolean parallel,int sdk){
        return sdk>=30&&(!parallel||sdk>=34);
    }
}
