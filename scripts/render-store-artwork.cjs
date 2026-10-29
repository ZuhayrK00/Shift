// Composes real simulator captures into vector layouts. Never redraws the app UI.
const fs = require('fs');
const path = require('path');
const sharp = require(process.env.SHARP_MODULE_PATH || 'sharp');
const root = path.resolve('output/app-store-2.1.0');
const raw = path.join(root,'raw'), out = path.join(root,'artwork');
const W=1320,H=2868,P='#b19aff',T='#40d1c3';
const xml = s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const data = file=>'data:image/png;base64,'+fs.readFileSync(path.join(raw,file+'.png')).toString('base64');
let serial=0;
function bg(accent, index) {
 let contours='';
 for(let i=0;i<11;i++) contours+=`<path d="M ${-400+i*80} 2868 C ${200+i*80} 2100, ${-300+i*80} 1700, ${800+i*80} 1450 S ${1400+i*80} 650, ${950+i*80} 200" fill="none" stroke="${accent}" stroke-opacity="${i%3===0?.11:.035}" stroke-width="${i%3===0?3:2}"/>`;
 return `<defs><radialGradient id="glow"><stop stop-color="${accent}" stop-opacity=".25"/><stop offset="1" stop-color="${accent}" stop-opacity="0"/></radialGradient><linearGradient id="base" x2=".8" y2="1"><stop stop-color="#111119"/><stop offset="1" stop-color="#030507"/></linearGradient><linearGradient id="rim"><stop stop-color="#74747c"/><stop offset=".18" stop-color="#27272d"/><stop offset=".65" stop-color="#0c0c10"/><stop offset="1" stop-color="#56565c"/></linearGradient><filter id="shadow" x="-40%" y="-30%" width="180%" height="170%"><feDropShadow dx="0" dy="40" stdDeviation="35" flood-color="#000" flood-opacity=".65"/></filter></defs><rect width="1320" height="2868" fill="url(#base)"/><ellipse cx="${index%2?1120:240}" cy="1500" rx="1200" ry="1500" fill="url(#glow)"/>${contours}<path d="M 92 180 L 1228 180" stroke="#fff" stroke-opacity=".13"/><text x="92" y="124" fill="#fff" font-size="45" font-weight="700">Shift<tspan fill="${accent}">.</tspan></text><text x="1228" y="122" text-anchor="end" fill="#a9a8b4" font-size="25" letter-spacing="4">${String(index).padStart(2,'0')} / FITNESS, TOGETHER</text>`;
}
function title(lines,sub,accent,{size=128,y=340}={}) {
 return lines.map((line,i)=>`<text x="92" y="${y+i*(size+8)}" font-size="${size}" font-weight="750" letter-spacing="-6" fill="${i===lines.length-1?accent:'#f6f5f9'}">${xml(line)}</text>`).join('')+sub.map((line,i)=>`<text x="96" y="${y+lines.length*(size+8)+50+i*56}" fill="#b1b0bc" font-size="40" letter-spacing="-.6">${xml(line)}</text>`).join('');
}
function phone(file,x,y,width=930,angle=0) {
 const id='screen'+serial++,h=width*2868/1320;
 return `<g transform="translate(${x} ${y}) rotate(${angle} ${width/2} ${h/2})" filter="url(#shadow)"><rect x="-20" y="-20" width="${width+40}" height="${h+40}" rx="${width*.108}" fill="url(#rim)" stroke="#9999a5" stroke-width="2"/><rect x="-8" y="-8" width="${width+16}" height="${h+16}" rx="${width*.1}" fill="#020203"/><clipPath id="${id}"><rect width="${width}" height="${h}" rx="${width*.093}"/></clipPath><image href="${data(file)}" width="${width}" height="${h}" clip-path="url(#${id})"/></g>`;
}
function foot(text,accent=P) {return `<circle cx="100" cy="2810" r="5" fill="${accent}"/><text x="122" y="2820" fill="#9c9ba8" font-size="28">${xml(text)}</text>`;}
function watch(file,x,y,width,angle=0) {
 const id='watch'+serial++,h=width*496/416;
 return `<g transform="translate(${x} ${y}) rotate(${angle} ${width/2} ${h/2})" filter="url(#shadow)"><rect x="${width*.19}" y="-270" width="${width*.62}" height="${h+540}" rx="85" fill="#141419" stroke="#393940" stroke-width="3"/><path d="M ${width*.23} -230 V ${h+235} M ${width*.77} -230 V ${h+235}" stroke="#555560" stroke-opacity=".35" stroke-width="2"/><rect x="-27" y="-27" width="${width+54}" height="${h+54}" rx="${width*.25}" fill="url(#rim)" stroke="#909099" stroke-width="3"/><rect x="${width+26}" y="${h*.27}" width="24" height="70" rx="10" fill="#6e6e78"/><rect x="-12" y="-12" width="${width+24}" height="${h+24}" rx="${width*.22}" fill="#000"/><clipPath id="${id}"><rect width="${width}" height="${h}" rx="${width*.20}"/></clipPath><image href="${data(file)}" width="${width}" height="${h}" clip-path="url(#${id})"/></g>`;
}
const slides = [
 {name:'01-train-your-way',accent:P,title:['Train your way.'],sub:['Strength. Endurance. One Shift.'],hero:true},
 {name:'02-every-set',accent:P,title:['Make every','set count.'],sub:['Plans, reps and weights.','Right there while you train.'],screen:'workout'},
 {name:'03-head-outside',accent:T,title:['Take it','outside.'],sub:['Runs, walks and rides.','Your route. Your pace. Your progress.'],screen:'route'},
 {name:'04-your-goals',accent:T,title:['Give your goals','some momentum.'],sub:['A little more distance.','A routine that keeps moving.'],screen:'goals',size:108},
 {name:'05-your-progress',accent:T,title:['Look how far','you’ve come.'],sub:['Follow your trends. Celebrate your bests.'],screen:'progress',pro:true},
 {name:'06-your-week',accent:P,title:['Make room','for your goals.'],sub:['Strength and Endurance,','together in your training calendar.'],screen:'calendar'},
 {name:'07-your-plan',accent:T,title:['A week that','works for you.'],sub:['Your availability. Better weather.','Fewer calendar clashes.'],screen:'planner',pro:true},
 {name:'08-your-widgets',accent:P,title:['Your next move.','At a glance.'],sub:['Keep your week close','with iPhone widgets.'],widgets:true,pro:true},
 {name:'09-your-watch',accent:T,title:['Train from','your wrist.'],sub:['Gym sessions and outdoor training.','On Apple Watch.'],watches:true,pro:true}
];
async function render() {
 fs.mkdirSync(out,{recursive:true});
 const rendered=[];
 for(let i=0;i<slides.length;i++) {
  const s=slides[i]; let body=bg(s.accent,i+1)+title(s.title,s.sub,s.accent,{size:s.size||128});
  if(s.hero) {
   body+=`<rect x="96" y="614" width="228" height="62" rx="31" fill="${P}" fill-opacity=".14"/><text x="210" y="655" text-anchor="middle" fill="${P}" font-size="25" letter-spacing="2">STRENGTH</text><rect x="342" y="614" width="260" height="62" rx="31" fill="${T}" fill-opacity=".14"/><text x="472" y="655" text-anchor="middle" fill="${T}" font-size="25" letter-spacing="2">ENDURANCE</text>`;
   body+=phone('strength',-10,910,700,-7)+phone('endurance',640,800,700,7);
   body+=`<text x="96" y="2684" fill="#f6f5f9" font-size="64" font-weight="650" letter-spacing="-2">Lift. Run. Walk. Ride.</text>`;
  } else if(s.widgets) {
   body+=phone('profile',515,880,710,5);
   // The screenshot is the running capture app hosting the extension's unmodified SwiftUI layouts.
   // Crop only the surrounding empty canvas, preserving every widget pixel and line of UI.
   body+=`<defs><clipPath id="widgetwide"><rect x="70" y="1120" width="1100" height="544" rx="86"/></clipPath><clipPath id="widgetsmall"><rect x="100" y="1800" width="560" height="560" rx="100"/></clipPath></defs><image href="${data('widget-wide')}" x="70" y="1120" width="1100" height="544" clip-path="url(#widgetwide)" filter="url(#shadow)"/><image href="${data('widget-small')}" x="100" y="1800" width="560" height="560" clip-path="url(#widgetsmall)" filter="url(#shadow)"/>`;
   body+=`<text x="100" y="2488" font-size="40" fill="${P}">One glance. Back to your day.</text>`;
  } else if(s.watches) {
   body+=watch('watch-recording',100,1230,540,-10)+watch('watch-home',730,1030,490,10);
   body+=`<text x="100" y="2530" fill="${T}" font-size="50" font-weight="600">Start. Record. Keep moving.</text>`;
  } else {body+=phone(s.screen,205,765,910,i%2===0?1.3:-1.3);}
  const footer=s.pro ? (s.screen==='planner'?'First generated week free. Continued planning with Shift Pro.':s.watches?'Apple Watch is included with Shift Pro.':s.widgets?'Widgets are included with Shift Pro.':'Longer-term trends with Shift Pro.') : 'Real app screens · fictional demonstration data';
  body+=foot(footer,s.accent);
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${H}" style="font-family:Helvetica Neue,Arial,sans-serif">${body}</svg>`;
  fs.writeFileSync(path.join(out,s.name+'.svg'),svg);
  await sharp(Buffer.from(svg)).flatten({background:'#09090f'}).png().toFile(path.join(out,s.name+'.png'));
  rendered.push(s.name); console.log('Rendered',s.name);
 }
 const thumbs=await Promise.all(rendered.map(n=>sharp(path.join(out,n+'.png')).resize(330,717).toBuffer()));
 await sharp({create:{width:1038,height:2223,channels:3,background:'#17171d'}}).composite(thumbs.map((input,i)=>({input,left:12+(i%3)*342,top:12+Math.floor(i/3)*741}))).png().toFile(path.join(root,'contact-sheet.png'));
 const html=`<!doctype html><meta charset="utf-8"><title>Shift — App Store preview</title><style>body{margin:0;background:#08090c;color:#eee;font:17px -apple-system,system-ui;padding:48px}h1{font-size:48px;letter-spacing:-2px}p{color:#a7a7b7;line-height:1.6;max-width:850px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:28px}img{width:100%;border-radius:16px}a{color:#b19aff;text-decoration:none}small{display:block;margin:12px 0 28px;color:#aaa}</style><h1>Shift. Fitness, together.</h1><p>App Store artwork preview. All phone and Watch interfaces are captured from the running native app with local fictional data. Widget artwork uses the extension’s actual SwiftUI layouts hosted in the capture build. Nothing in this set has been uploaded yet.</p><div class="grid">${rendered.map((n,i)=>`<a href="artwork/${n}.png"><img src="artwork/${n}.png"><small>${i+1}. ${n.slice(3).replaceAll('-',' ')}</small></a>`).join('')}</div>`;
 fs.writeFileSync(path.join(root,'preview.html'),html);
}
render().catch(e=>{console.error(e.message);process.exitCode=1});
