const puppeteer = require('puppeteer');
const fs = require('fs');

(async () => {
  const fps = 30;                // Frames per second
  const duration = 6;            // Duration in seconds
  const totalFrames = fps * duration;
  const svgFilePath = 'spinny-smaller.svg';
  const outputDir = 'frames';

  if (!fs.existsSync(outputDir)){
    fs.mkdirSync(outputDir);
  }

  const svgContent = fs.readFileSync(svgFilePath, 'utf8');

  const browser = await puppeteer.launch();
  const page = await browser.newPage();

  await page.setViewport({ width: 100, height: 100 });

  await page.setContent(`
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }
          html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: transparent;
          }
          body {
            display: flex;
            justify-content: center;
            align-items: center;
          }
          svg {
            display: block;
          }
        </style>
      </head>
      <body>
        ${svgContent}
      </body>
    </html>
  `);

  const svgElement = await page.$('svg');

  const setAnimationProgress = async (progress) => {
    await page.evaluate((progress) => {
      document.documentElement.style.setProperty('--animation-progress', progress);
    }, progress);
  };

  await page.evaluate(() => {
    const style = document.createElement('style');
    style.innerHTML = `
      * {
        animation-play-state: paused !important;
      }
    `;
    document.head.appendChild(style);
  });

  for (let frame = 0; frame < totalFrames; frame++) {
    const progress = (frame / totalFrames) * duration;

    await page.evaluate((currentTime) => {
      document.querySelectorAll('*').forEach((element) => {
        element.getAnimations().forEach((animation) => {
          animation.currentTime = currentTime * 1000;
        });
      });
    }, progress);

    const screenshotPath = `${outputDir}/frame_${String(frame).padStart(3, '0')}.png`;
    await svgElement.screenshot({ path: screenshotPath, omitBackground: true });

    console.log(`Captured frame ${frame + 1} / ${totalFrames}`);
  }

  await browser.close();
})();

