// Fails the build if the apps differ from the HTML game (subjects, questions, rules).
const fs=require('fs');
const rd=f=>fs.readFileSync(f,'utf8');
const src=rd('src/BrainLAN.html'),inj=rd('tools/teacher-inject.html');
const subj=h=>[...(h.match(/id="sCat"[^>]*>(.*?)<\/select>/s)||['',''])[1].matchAll(/<option[^>]*>([^<]*)<\/option>/g)].map(m=>m[1]);
const bank=h=>(h.match(/const BANK=.*\n/)||[''])[0];
const S=subj(src);
console.log('Subjects in HTML ('+S.length+'):',S.join(', '));
if(S.filter(s=>s!=='Custom').length!==9)throw new Error('Expected 9 subjects + Custom');
if(rd('www/index.html').replace(inj,'')!==src)throw new Error('Teacher app differs from HTML');
for(const f of ['www/index.html','www/student.html','www-student/index.html']){
  const h=rd(f);
  if(subj(h).join()!==S.join())throw new Error(f+': subject list differs');
  if(bank(h)!==bank(src))throw new Error(f+': question banks differ');
  if(h.length<src.length)throw new Error(f+': content missing');
}
console.log('OK: teacher app, student web page and student app all contain the same 9 subject banks as the HTML.');
