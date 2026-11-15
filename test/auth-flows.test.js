import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
const app=readFileSync(new URL('../src/App.jsx',import.meta.url),'utf8');
test('account UI wires email OTP, password recovery, and Google/Apple OAuth flows',()=>{
 for(const api of ['auth.signUp','auth.verifyOtp','auth.signInWithPassword','auth.signInWithOtp','auth.resetPasswordForEmail','auth.signInWithOAuth','auth.updateUser']) assert.ok(cloud.includes(api),api);
 assert.ok(cloud.includes("setOtpType('signup')"));
 assert.ok(cloud.includes("setOtpType('email')"));
 assert.ok(cloud.includes("type:otpType"));
 assert.ok(cloud.includes("shouldCreateUser:false"));
 assert.ok(cloud.includes('loginCode:'));
 assert.ok(cloud.includes("provider,options:{redirectTo:window.location.origin+import.meta.env.BASE_URL}"));
});

test('password recovery requires a confirmed password of at least eight characters',()=>{
 assert.ok(cloud.includes('confirmNewPassword'));
 assert.ok(cloud.includes("newPassword!==confirmNewPassword"));
 assert.ok(cloud.includes('newPassword.length<8'));
 assert.ok(cloud.includes("placeholder={ar?'تأكيد كلمة المرور':'Confirm password'}"));
});

test('the app requires an authenticated Supabase session before showing any play mode',()=>{
 assert.ok(app.includes("import CloudDashboard from './CloudDashboard.jsx'"));
 assert.ok(app.includes("import { isCloudConfigured, supabase } from './cloud/supabase.js'"));
 assert.ok(app.includes("supabase.auth.getSession()"));
 assert.ok(app.includes("supabase.auth.onAuthStateChange"));
 assert.ok(app.includes("if(!authSession?.user||authRecovery)return"));
 assert.ok(app.includes("setAuthRecovery(true)"));
 assert.ok(app.includes("event==='PASSWORD_RECOVERY'"));
 assert.ok(app.includes("event==='USER_UPDATED'"));
 assert.ok(app.includes('<CloudDashboard section="account"'));
 assert.ok(app.indexOf("if(!authSession?.user||authRecovery)return")<app.indexOf("if(localMode)return"));
 assert.ok(cloud.includes("const address=email.trim()"));
 assert.ok(cloud.includes("Enter your email address first"));
 assert.ok(cloud.includes("redirectTo:window.location.origin+import.meta.env.BASE_URL"));
 assert.ok(cloud.includes("provider is not enabled"));
 assert.ok(cloud.includes("Google and Apple sign-in require provider credentials"));
});
