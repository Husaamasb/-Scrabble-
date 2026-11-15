import React,{useState} from 'react';
import {supabase} from './cloud/supabase.js';
export default function ReportForm({user,language}){
 const ar=language==='ar',tr=(a,e)=>ar?a:e;
 const [category,setCategory]=useState('cheating'),[details,setDetails]=useState(''),[publicId,setPublicId]=useState(''),[roomCode,setRoomCode]=useState(''),[busy,setBusy]=useState(false),[notice,setNotice]=useState('');
 const submit=async event=>{event.preventDefault();if(!user?.id||details.trim().length<5)return;setBusy(true);setNotice('');try{
  let target_user_id=null,room_id=null;
  if(publicId.trim()){const {data,error}=await supabase.from('profiles').select('id').eq('public_id',publicId.trim().toUpperCase()).maybeSingle();if(error)throw error;if(!data)throw new Error(tr('رقم اللاعب غير موجود','Player ID not found'));target_user_id=data.id;}
  if(roomCode.trim()){const {data,error}=await supabase.from('rooms').select('id').eq('code',roomCode.trim()).maybeSingle();if(error)throw error;if(!data)throw new Error(tr('رمز الغرفة غير موجود','Room code not found'));room_id=data.id;}
  const {error}=await supabase.from('scrabble_player_reports').insert({reporter_id:user.id,target_user_id,room_id,category,details:details.trim()});if(error)throw error;
  setDetails('');setPublicId('');setRoomCode('');setNotice(tr('وصل البلاغ للإدارة. شكرًا لك.','Your report was sent to the admin team.'));
 }catch(error){setNotice(error.message||tr('تعذر إرسال البلاغ','Could not submit report'));}finally{setBusy(false);}};
 return <section className="report-panel" dir={ar?'rtl':'ltr'}><h3>{tr('الإبلاغ عن لاعب أو غرفة','Report a player or room')}</h3><form onSubmit={submit}>
  <label>{tr('نوع البلاغ','Report type')}<select value={category} onChange={e=>setCategory(e.target.value)}><option value="cheating">{tr('غش في اللعب','Cheating')}</option><option value="abuse">{tr('إساءة أو مضايقة','Abuse')}</option><option value="inappropriate_name">{tr('اسم غير مناسب','Inappropriate name')}</option><option value="other">{tr('سبب آخر','Other')}</option></select></label>
  <label>{tr('رقم اللاعب (اختياري)','Player ID (optional)')}<input value={publicId} onChange={e=>setPublicId(e.target.value)} maxLength="16"/></label>
  <label>{tr('رمز الغرفة (اختياري)','Room code (optional)')}<input value={roomCode} onChange={e=>setRoomCode(e.target.value)} maxLength="12"/></label>
  <label>{tr('اشرح المشكلة','Describe the issue')}<textarea value={details} onChange={e=>setDetails(e.target.value)} minLength="5" maxLength="1000" required/></label>
  <button type="submit" disabled={busy||details.trim().length<5}>{busy?tr('جارٍ الإرسال…','Sending…'):tr('إرسال البلاغ','Submit report')}</button>
 </form>{notice&&<p className="report-notice">{notice}</p>}</section>;
}
