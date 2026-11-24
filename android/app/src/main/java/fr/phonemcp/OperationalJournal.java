package fr.phonemcp;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.*;
import java.util.regex.Pattern;

/** Private, owner-scoped operational checkpoints. No app content, credentials or input replay. */
final class OperationalJournal {
    private static final Pattern OWNER=Pattern.compile("[a-f0-9]{64}");
    private static final Pattern ID=Pattern.compile("[A-Za-z0-9_-]{1,64}");
    private static final int MAX_RECORDS=100,MAX_RECORD_BYTES=12000;
    private static String bounded(JSONObject object,String field,int maximum)throws JSONException{
        String value=object.getString(field);
        if(value.length()==0||value.length()>maximum)throw new IllegalArgumentException("Invalid "+field);
        return value;
    }
    static synchronized JSONObject execute(Context context,String op,JSONObject args)throws Exception{
        String owner=args.optString("_ownerKey");
        if(!OWNER.matcher(owner).matches())throw new SecurityException("Operational journal owner required.");
        SharedPreferences storage=context.getSharedPreferences("charles_operational_journal_"+owner,Context.MODE_PRIVATE);
        String id=args.optString("recordId");
        if(!id.isEmpty()&&!ID.matcher(id).matches())throw new IllegalArgumentException("Invalid record ID.");
        if("journal_read".equals(op)){
            if(!id.isEmpty()){
                String raw=storage.getString(id,null);
                return new JSONObject().put("found",raw!=null).put("record",raw==null?JSONObject.NULL:new JSONObject(raw));
            }
            JSONArray records=new JSONArray();
            java.util.ArrayList<String> keys=new java.util.ArrayList<>(storage.getAll().keySet());
            java.util.Collections.sort(keys);
            int offset=args.optInt("offset",0),limit=args.optInt("limit",20);
            if(offset<0||limit<1||limit>50)throw new IllegalArgumentException("Invalid pagination.");
            for(int i=offset;i<keys.size()&&i<offset+limit;i++){
                JSONObject value=new JSONObject(storage.getString(keys.get(i),"{}"));
                records.put(new JSONObject().put("recordId",keys.get(i)).put("revision",value.getInt("revision")).put("type",value.getString("type")).put("label",value.getString("label")).put("updatedAt",value.getLong("updatedAt")));
            }
            return new JSONObject().put("records",records).put("total",keys.size()).put("offset",offset);
        }
        if(!"journal_write".equals(op)||id.isEmpty())throw new IllegalArgumentException("Invalid journal action.");
        JSONObject record=args.getJSONObject("record");
        if(record.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8).length>MAX_RECORD_BYTES)throw new IllegalArgumentException("Record too large.");
        String type=bounded(record,"type",20),label=bounded(record,"label",120);
        if(!"checkpoint".equals(type)&&!"procedure".equals(type))throw new IllegalArgumentException("Unsupported record type.");
        String old=storage.getString(id,null);
        int revision=old==null?0:new JSONObject(old).getInt("revision");
        if(args.getInt("expectedRevision")!=revision)throw new IllegalStateException("Journal revision changed; read before updating.");
        if(old==null&&storage.getAll().size()>=MAX_RECORDS)throw new IllegalStateException("Journal limit reached.");
        JSONObject clean=new JSONObject().put("recordId",id).put("type",type).put("label",label).put("revision",revision+1).put("updatedAt",System.currentTimeMillis());
        if("checkpoint".equals(type)){
            JSONArray items=record.getJSONArray("items");
            if(items.length()>250)throw new IllegalArgumentException("Too many checkpoint items.");
            JSONArray safe=new JSONArray();java.util.HashSet<String> seen=new java.util.HashSet<>();
            for(int i=0;i<items.length();i++){
                JSONObject item=items.getJSONObject(i);String key=bounded(item,"id",64),status=bounded(item,"status",20);
                if(!ID.matcher(key).matches()||!seen.add(key)||!java.util.Arrays.asList("pending","verified","failed","uncertain").contains(status))throw new IllegalArgumentException("Invalid checkpoint item.");
                safe.put(new JSONObject().put("id",key).put("status",status));
            }
            clean.put("items",safe);
        }else{
            String pkg=bounded(record,"packageName",240);
            if(!AccessPolicy.validPackage(pkg))throw new IllegalArgumentException("Invalid procedure application.");
            JSONArray steps=record.getJSONArray("steps");
            if(steps.length()<1||steps.length()>8)throw new IllegalArgumentException("Invalid procedure length.");
            JSONArray safe=new JSONArray();
            for(int i=0;i<steps.length();i++){
                JSONObject step=steps.getJSONObject(i);
                String action=bounded(step,"op",20),query=bounded(step,"query",250),by=bounded(step,"by",20);
                if(!java.util.Arrays.asList("wait_and_click","wait_for").contains(action)||!java.util.Arrays.asList("text","description","viewId").contains(by))throw new IllegalArgumentException("Invalid procedure step.");
                safe.put(new JSONObject().put("op",action).put("query",query).put("by",by));
            }
            clean.put("packageName",pkg).put("steps",safe);
        }
        if(!storage.edit().putString(id,clean.toString()).commit())throw new IllegalStateException("Journal write was not confirmed.");
        JSONObject actual=new JSONObject(storage.getString(id,"{}"));
        if(actual.optInt("revision",-1)!=revision+1)throw new IllegalStateException("Journal verification failed.");
        return new JSONObject().put("saved",true).put("record",actual).put("automaticReplay",false);
    }
}
