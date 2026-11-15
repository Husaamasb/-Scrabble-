import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const cloud=readFileSync(new URL('../src/CloudDashboard.jsx',import.meta.url),'utf8');
test('account UI wires email OTP, password recovery, and Google/Apple OAuth flows',()=>{
 for(const api of ['auth.signUp','auth.verifyOtp','auth.signInWithPassword','auth.resetPasswordForEmail','auth.signInWithOAuth','auth.updateUser']) assert.ok(cloud.includes(api),api);
 assert.ok(cloud.includes("type:'signup'"));
 assert.ok(cloud.includes("provider,options:{redirectTo:location.href}"));
});

test('password recovery requires a confirmed password of at least eight characters',()=>{
 assert.ok(cloud.includes('confirmNewPassword'));
 assert.ok(cloud.includes("newPassword!==confirmNewPassword"));
 assert.ok(cloud.includes('newPassword.length<8'));
 assert.ok(cloud.includes("placeholder={ar?'تأكيد كلمة المرور':'Confirm password'}"));
});
