// Reproducible, offline extraction. Never reads the application's databases.
// Usage: node dev/gallery/extract_demo.cjs <TrafArch-UI-Redesign directory>
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const sourceRoot = process.argv[2];
if (!sourceRoot) throw Error('Pass the design workspace directory');
const sourcePath = path.join(sourceRoot, 'design-demos/2.4.0-single-Trafarch.html');
const source = fs.readFileSync(sourcePath, 'utf8');
const script = source.match(/<script>([\s\S]*?)<\/script>/)[1];
const el = {dataset:{initial:'home'},innerHTML:'',querySelector:()=>null,querySelectorAll:()=>[],addEventListener(){}};
class DemoDate extends Date { static now() { return Date.parse('2026-10-27T09:41:00+08:00'); } }
const context = vm.createContext({Date:DemoDate,URLSearchParams,location:{search:'?read=1'},matchMedia:()=>({matches:false,addEventListener(){}}),document:{querySelectorAll:()=>[el]},setTimeout:()=>0,clearTimeout(){},Blob,URL,console});
vm.runInContext(script, context);
const run = code => vm.runInContext(code, context);
const data = JSON.parse(run('JSON.stringify({cards:CARDS,trips:DATA.trips,ledgers:CARD_LEDGER,raw:CARD_RAW,rawFields:RAW_FIELDS,footprints:FOOTPRINTS,palettes:PALETTES,sources:SOURCES,modes:MODES,expertTabs:TABS,knowledge:KNOWLEDGE,qrValid:qrFixture(false),qrExpired:qrFixture(true)})'));
run(`globalThis.sections=[]; expertSection=(title,rows,open=true,extra='')=>{sections.push({title,rows,open,extra});return '';};`);
data.expert = {};
for (const kind of ['card','bank','felica']) {
  run(`sections=[];expertInformation({expertKind:'${kind}'});`);
  data.expert[kind] = JSON.parse(run('JSON.stringify(sections)'));
}
run('sections=[];expertTransit();');
data.expert.transit = JSON.parse(run('JSON.stringify(sections)'));
const definitionsSource = fs.readFileSync(path.join(sourceRoot,'figma-import/source/capture.cjs'),'utf8');
const definitions = definitionsSource.slice(definitionsSource.indexOf('const definitions='), definitionsSource.indexOf('const assets='));
data.scenes = vm.runInNewContext(definitions+'\ndefinitions');
data.provenance = {designVersion:'2.4.0',source:'2.4.0-single-Trafarch.html',sha256:crypto.createHash('sha256').update(source).digest('hex'),clock:'2026-10-27T09:41:00+08:00',knowledgeCaptured:data.knowledge.captured};
const output=path.join(root,'assets/gallery');
fs.mkdirSync(output,{recursive:true});
fs.writeFileSync(path.join(output,'fixtures.json'),JSON.stringify(data,null,2)+'\n');
fs.copyFileSync(path.join(sourceRoot,'design-demos/assets/tunion-logo.svg'),path.join(output,'tunion-logo.svg'));
// The schematic is an existing design asset, not a geographic basemap.
const schematic=source.match(/<svg class="city-map"[\s\S]*?<\/svg>/)[0];
fs.writeFileSync(path.join(output,'footprints-map.svg'),schematic.replace('class="city-map"','xmlns="http://www.w3.org/2000/svg"').replace(/var\(--[^)]+\)/g,'#61738A').replace('<path class="water"','<path fill="#263B50"').replace('<path class="block"','<path fill="#1B2634"').replace('<path class="minor"','<path fill="none" stroke="#334255" stroke-width="1"').replace('<path class="major"','<path fill="none" stroke="#50677D" stroke-width="2"').replace('<text ','<text fill="#93A0B4" font-size="12" '));
console.log(JSON.stringify({scenes:data.scenes.length,cards:data.cards.length,qrBytes:data.qrValid.raw.length,knowledge:data.knowledge.captured,output}));
