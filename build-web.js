// One source (src/BrainLAN.html) -> three builds. Game content is never edited, only wrapped.
//  www/index.html          iPhone TEACHER app (PIN + Zapier)
//  www/student.html        served by the teacher's iPhone to any browser (fallback)
//  www-student/index.html  Android STUDENT app (APK)
const fs=require('fs');
const src=fs.readFileSync('src/BrainLAN.html','utf8');
const inj=fs.readFileSync('tools/teacher-inject.html','utf8');
const w=(f,s)=>{fs.mkdirSync(f.split('/')[0],{recursive:true});fs.writeFileSync(f,s)};
const must=(s,a,b)=>{if(!s.includes(a))throw new Error('Patch target missing: '+a);return s.replace(a,b)};
const i=src.lastIndexOf('</body>');
w('www/index.html',src.slice(0,i)+inj+src.slice(i));
const hide='<style>#hostBtn{display:none!important}</style></head>';
const web=src.replace('</head>',hide);
w('www/student.html',web);
let app=must(web,"a+=':3000'","a+=':8080'");
app=must(app,'192.168.43.100:3000','172.20.10.1:8080');
app=must(app,'● Teacher: host from this iPhone · Student: join with the teacher address','● Student: type the teacher address, then join');
w('www-student/index.html',app);
console.log('built teacher app, student web page, student app');
