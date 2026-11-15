import { createSupabaseContext } from "npm:@supabase/server@1.6.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(data: unknown, status=200) {
  return new Response(JSON.stringify(data),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
}

Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST")return json({error:"Method not allowed."},405);
  try{
    const {data:ctx,error:contextError}=await createSupabaseContext(req,{auth:"user"});
    if(contextError||!ctx)return json({error:"Sign in required."},contextError?.status||401);
    const {data:userData,error:userError}=await ctx.supabase.auth.getUser();
    const actor=userData?.user;
    if(userError||!actor)return json({error:"Sign in required."},401);
    if(actor.app_metadata?.scrabble_admin!==true)return json({error:"Administrator access required."},403);

    const body=await req.json();
    const action=String(body?.action||"");
    if(action==="list_players"){
      const {data,error}=await ctx.supabaseAdmin.auth.admin.listUsers({page:1,perPage:100});
      if(error)throw error;
      const users=(data?.users||[]).map((u:any)=>({
        id:u.id,email:u.email||"",banned_until:u.banned_until||null,
        last_sign_in_at:u.last_sign_in_at||null,created_at:u.created_at||null,
        is_admin:u.app_metadata?.scrabble_admin===true,
      }));
      return json({users});
    }

    const targetId=String(body?.target_user_id||"");
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId)){
      return json({error:"Invalid player ID."},400);
    }
    const {data:targetData,error:targetError}=await ctx.supabaseAdmin.auth.admin.getUserById(targetId);
    if(targetError||!targetData?.user)return json({error:"Player not found."},404);
    if(targetData.user.app_metadata?.scrabble_admin===true)return json({error:"Administrator accounts cannot be moderated here."},403);
    if(targetId===actor.id)return json({error:"You cannot suspend your own account."},403);

    if(action==="ban_user"){
      const duration=String(body?.duration||"24h");
      if(!["24h","168h","720h"].includes(duration))return json({error:"Unsupported suspension duration."},400);
      const {error}=await ctx.supabaseAdmin.auth.admin.updateUserById(targetId,{ban_duration:duration});
      if(error)throw error;
      return json({ok:true,action,duration});
    }
    if(action==="unban_user"){
      const {error}=await ctx.supabaseAdmin.auth.admin.updateUserById(targetId,{ban_duration:"none"});
      if(error)throw error;
      return json({ok:true,action});
    }
    return json({error:"Unknown admin action."},400);
  }catch(error){
    console.error("scrabble-admin:",error);
    return json({error:error instanceof Error?error.message:"Admin operation failed."},500);
  }
});
