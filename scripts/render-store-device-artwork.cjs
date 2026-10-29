// Real iPad / Watch simulator captures, composed without replacing or redrawing app UI.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require(process.env.SHARP_MODULE_PATH || 'sharp');
const root = path.resolve('output/app-store-2.1.1-devices');
const out = path.join(root, 'artwork');
const W = 2064, H = 2752, P = '#b19aff', T = '#40d1c3';
const esc = s => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const data = file => 'data:image/png;base64,' + fs.readFileSync(path.join(root, 'raw', file + '.png')).toString('base64');
const slides = [
  { name: '01-strength', screen: 'strength', accent: P, lines: ['Build your strength.'], sub: 'Your plans. Your sets. Your next personal best.' },
  { name: '02-endurance', screen: 'endurance', accent: T, lines: ['Take your training outside.'], sub: 'Run, walk and ride. All together in Shift.' },
  { name: '03-workout', screen: 'workout', accent: P, lines: ['Make every set count.'], sub: 'Log weights and reps. Keep your session moving.' },
  { name: '04-route', screen: 'route', accent: T, lines: ['Every route tells a story.'], sub: 'Your distance, pace and splits. Right there on the map.' },
  { name: '05-goals', screen: 'goals', accent: T, lines: ['Give your goals momentum.'], sub: 'More distance. More consistency. Your kind of progress.' },
  { name: '06-progress', screen: 'progress', accent: T, lines: ['Look how far you’ve come.'], sub: 'Follow your trends. Celebrate your bests.', pro: 'Longer-term trends with Shift Pro.' },
  { name: '07-calendar', screen: 'calendar', accent: P, lines: ['Make room for your goals.'], sub: 'Strength and Endurance, together in your training calendar.' },
  { name: '08-your-week', screen: 'planner', accent: T, lines: ['A week that works for you.'], sub: 'Your availability. Better weather. Fewer calendar clashes.', pro: 'First generated week free. Continued planning with Shift Pro.' },
  { name: '09-weather-changes', screen: 'weather-changes', accent: T, lines: ['Forecast changed?', 'Keep your week moving.'], sub: 'Review a better time. You decide whether to move.', pro: 'Forecast change suggestions with Shift Pro. Opt in for each plan.' }
];
function bg(accent) {
  return `<defs><linearGradient id="base" x2="1" y2="1"><stop stop-color="#12131e"/><stop offset="1" stop-color="#040608"/></linearGradient><radialGradient id="glow"><stop stop-color="${accent}" stop-opacity=".22"/><stop offset="1" stop-color="${accent}" stop-opacity="0"/></radialGradient><linearGradient id="rim"><stop stop-color="#777b84"/><stop offset=".18" stop-color="#30323a"/><stop offset=".7" stop-color="#101116"/><stop offset="1" stop-color="#565b64"/></linearGradient><filter id="shadow" x="-30%" y="-20%" width="160%" height="150%"><feDropShadow dx="0" dy="36" stdDeviation="40" flood-opacity=".65"/></filter></defs><rect width="${W}" height="${H}" fill="url(#base)"/><ellipse cx="1800" cy="1350" rx="1400" ry="1600" fill="url(#glow)"/>${Array.from({length:12},(_,i)=>`<path d="M ${-600+i*110} 2752 C ${200+i*100} 2100, ${-100+i*90} 1600, ${1100+i*100} 1000 S ${2100+i*90} 300, ${1200+i*100} 0" stroke="${accent}" stroke-opacity="${i%3===0?'.09':'.03'}" stroke-width="2" fill="none"/>`).join('')}`;
}
function tablet(screen, y, width, height) {
  const x = (W-width)/2;
  return `<g filter="url(#shadow)"><rect x="${x-30}" y="${y-30}" width="${width+60}" height="${height+60}" rx="62" fill="url(#rim)" stroke="#777c85" stroke-width="2"/><rect x="${x-23}" y="${y-23}" width="${width+46}" height="${height+46}" rx="56" fill="#08090b"/><clipPath id="display"><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="35"/></clipPath><image href="${data('ipad/'+screen)}" x="${x}" y="${y}" width="${width}" height="${height}" clip-path="url(#display)"/><circle cx="${W/2}" cy="${y-16}" r="4" fill="#252933"/></g>`;
}
async function main() {
  fs.mkdirSync(path.join(out,'ipad'),{recursive:true});
  fs.mkdirSync(path.join(out,'watch'),{recursive:true});
  const hashes = {}, assets=[];
  for (const [i,s] of slides.entries()) {
    const long=s.lines.length>1, y=long?670:515, height=long?1940:2090, width=height*2064/2752;
    let body=bg(s.accent)+`<text x="112" y="118" fill="#fff" font-size="54" font-weight="750">Shift<tspan fill="${s.accent}">.</tspan></text><text x="1952" y="115" text-anchor="end" fill="#a9a8b4" font-size="27" letter-spacing="4">${String(i+1).padStart(2,'0')} / FITNESS, TOGETHER</text><path d="M112 170H1952" stroke="#fff" stroke-opacity=".14"/>`;
    body+=s.lines.map((line,j)=>`<text x="112" y="${315+j*145}" font-size="${long?123:120}" font-weight="750" letter-spacing="-5" fill="${long&&j===0?'#f5f5fa':s.accent}">${esc(line)}</text>`).join('');
    body+=`<text x="116" y="${long?550:410}" fill="#b9bac6" font-size="40">${esc(s.sub)}</text>`;
    body+=tablet(s.screen,y,width,height);
    body+=`<circle cx="118" cy="2694" r="6" fill="${s.accent}"/><text x="140" y="2704" fill="#a1a3b0" font-size="27">${esc(s.pro||'Real iPad app screens · fictional demonstration data')}</text>`;
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" style="font-family:Helvetica Neue,Arial,sans-serif">${body}</svg>`;
    fs.writeFileSync(path.join(out,'ipad',s.name+'.svg'),svg);
    const dest=path.join(out,'ipad',s.name+'.png');
    await sharp(Buffer.from(svg)).flatten({background:'#08090e'}).removeAlpha().png().toFile(dest);
    assets.push(dest);
    console.log('Rendered iPad',s.name);
  }
  const watches=[['01-home','home','Your training, together'],['02-strength','gym','Your gym session'],['03-sets','sets','Log your sets'],['04-recording','recording','Record from your wrist']];
  for (const file of fs.readdirSync(path.join(out,'watch'))) {
    if(file.endsWith('.png')&&!watches.some(([name])=>file===name+'.png'))fs.unlinkSync(path.join(out,'watch',file));
  }
  for(const [name,screen] of watches) {
    const source=path.join(root,'raw','watch',screen+'.png'), dest=path.join(out,'watch',name+'.png');
    const meta=await sharp(source).metadata();
    if(meta.width!==416||meta.height!==496)throw Error('Unexpected Watch capture size');
    await sharp(source).flatten({background:'#000'}).removeAlpha().png().toFile(dest);
  }
  const thumbs=await Promise.all(assets.map(p=>sharp(p).resize(387,516).toBuffer()));
  await sharp({create:{width:1215,height:1638,channels:3,background:'#090b11'}}).composite(thumbs.map((input,i)=>({input,left:15+(i%3)*399,top:15+Math.floor(i/3)*540}))).png().toFile(path.join(root,'ipad-contact-sheet.png'));
  // Presentation board only: Watch uploads remain full-canvas native screenshots.
  const cards=await Promise.all(watches.map(async([name,screen,label],i)=>{
    const accent=i===1?P:T, sx=38,sy=155,sw=416,sh=496;
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="492" height="760" style="font-family:Helvetica Neue,Arial,sans-serif"><rect width="492" height="760" rx="28" fill="#11151d"/><text x="38" y="65" fill="${accent}" font-size="20" letter-spacing="2">SHIFT / APPLE WATCH</text><text x="38" y="110" fill="#fff" font-size="27" font-weight="650">${esc(label)}</text><rect x="${sx-8}" y="${sy-8}" width="${sw+16}" height="${sh+16}" rx="62" fill="#2c313a"/><clipPath id="watchscreen"><rect x="${sx}" y="${sy}" width="${sw}" height="${sh}" rx="54"/></clipPath><image href="${data('watch/'+screen)}" x="${sx}" y="${sy}" width="${sw}" height="${sh}" clip-path="url(#watchscreen)"/><text x="38" y="712" fill="#a5adba" font-size="21">Real app · fictional demo data</text></svg>`;
    return sharp(Buffer.from(svg)).png().toBuffer();
  }));
  await sharp({create:{width:2052,height:796,channels:3,background:'#080a10'}}).composite(cards.map((input,i)=>({input,left:18+i*508,top:18}))).png().toFile(path.join(root,'watch-contact-sheet.png'));
  for(const family of ['ipad','watch'])for(const file of fs.readdirSync(path.join(root,'raw',family)))if(file.endsWith('.png'))hashes[`raw/${family}/${file}`]=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'raw',family,file))).digest('hex');
  fs.writeFileSync(path.join(root,'capture-manifest.json'),JSON.stringify({version:'2.1.1 (25)',capturedAt:new Date().toISOString(),account:'Local fictional Alex Morgan; no Supabase session or customer data',ipad:'iPad Pro 13-inch M5, iPadOS 26.5, 2064×2752',watch:'Apple Watch Series 11 46mm, watchOS 27, 416×496',seed:{gymSessions:64,outdoorActivities:84,plans:4,weightEntries:28,enduranceGoals:3,upcomingSessions:8},normalBuild:'Capture helpers are compiled only with SHIFT_STORE_CAPTURE and targetEnvironment(simulator).',provenance:'All device interfaces captured from the running native app. iPad background, headline and bezel are artwork. Watch upload images contain only the native screen; the labeled Watch contact sheet is a review board.',rawCaptureSHA256:hashes},null,2));
  fs.writeFileSync(path.join(root,'preview.html'),`<!doctype html><meta charset="utf-8"><title>Shift — iPad & Watch App Store artwork</title><style>body{margin:0;padding:48px;background:#080a10;color:#f5f5fa;font:18px -apple-system,system-ui}h1{font-size:48px;letter-spacing:-2px}p{max-width:920px;line-height:1.6;color:#acb1be}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}.grid img{width:100%;border-radius:18px}a{color:#40d1c3}h2{margin-top:60px}small{display:block;margin:12px;color:#acb1be}.watch{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:24px}.watch img{width:100%;max-width:416px}img.board{width:100%;margin-top:24px}</style><h1>Shift. A bigger picture.</h1><p>Nine new iPad images and four refreshed Apple Watch screens, captured from the running native app with fictional demonstration data. Full device screens remain visible. Prepared for review; these images have not been uploaded.</p><h2>iPad · 13-inch</h2><div class="grid">${slides.map(s=>`<a href="artwork/ipad/${s.name}.png"><img src="artwork/ipad/${s.name}.png"><small>${esc(s.lines.join(' '))}</small></a>`).join('')}</div><h2>Apple Watch · actual upload images</h2><p>The Watch set uses full-size native screens to keep its small text readable. Apple Watch features require Shift Pro.</p><div class="watch">${watches.map(([name,screen,label])=>`<a href="artwork/watch/${name}.png"><img src="artwork/watch/${name}.png"><small>${esc(label)}</small></a>`).join('')}</div><h2>Watch presentation board</h2><p>This labeled board is for reviewing the set; the four individual native screens above are the Watch uploads.</p><img class="board" src="watch-contact-sheet.png">`);
}
main().catch(e=>{console.error(e);process.exitCode=1});
