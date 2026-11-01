// Design-artifact renderer. Uses an externally installed Playwright; no app dependencies.
import { createRequire } from 'node:module';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.dirname(fileURLToPath(import.meta.url));
const screens = JSON.parse(await readFile(path.join(root, 'screens.json'), 'utf8'));
await mkdir(path.join(root, 'screenshots'), { recursive: true });
const browser = await chromium.launch({executablePath:process.env.CHROME_BIN || '/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
const page = await browser.newPage({viewport:{width:402,height:874},deviceScaleFactor:2});
const errors=[];
page.on('pageerror', e=>errors.push(e.message));
page.on('requestfailed', r=>errors.push(`${r.url()}: ${r.failure()?.errorText}`));
const findings=[];
for (const screen of screens) {
  await page.goto(pathToFileURL(path.join(root, `${screen.slug}.html`)).href);
  await page.screenshot({path:path.join(root,'screenshots',`${screen.slug}.png`)});
  const issue=await page.evaluate(()=>{
    const frame=document.querySelector('.phone').getBoundingClientRect();
    const content=document.querySelector('.content');
    const bad=[...document.querySelectorAll('h1,h2,p,.row,.note,.button,input')].filter(e=>{
      if(e.closest('.overlay')===null && document.querySelector('.overlay'))return false;
      const r=e.getBoundingClientRect();return r.right>frame.right+1||r.left<frame.left-1||r.bottom>frame.bottom-20;
    }).map(e=>e.textContent.trim().slice(0,80));
    return {overflow:content.scrollHeight>content.clientHeight+1,outside:bad};
  });
  findings.push({screen:screen.slug,...issue});
}
await page.setViewportSize({width:1600,height:1100});
await page.goto(pathToFileURL(path.join(root,'index.html')).href);
await page.evaluate(async()=>{for(const i of document.images){i.loading='eager';await i.decode();}});
await page.screenshot({path:path.join(root,'screenshots','contact-sheet.png'),fullPage:true});
await browser.close();
const report={renderer:'Headless Chromium via Playwright',viewport:'402 × 874 CSS px',scale:2,screenCount:screens.length,errors,findings};
await writeFile(path.join(root,'render-report.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
if(errors.length||findings.some(x=>x.outside.length||x.overflow))process.exitCode=1;
