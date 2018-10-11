const {webdriver, Builder, By, Key, until} = require('selenium-webdriver'),
  test = require('selenium-webdriver/testing'),
  assert = require('assert');

  test.describe('PortfolioTestsAsyncAwait', function() {
      test.before(async function () {
        driver = await new Builder().forBrowser('chrome').build();
      });

      test.it('01 Drums Access Await', async function () {
        await driver.get("https://andreidbr.github.io/JS30/");

        const drumsLink = await driver.findElement(By.xpath('/html/body/div[2]/div[1]'));
        await drumsLink.click();

        const pageTitle = await driver.getTitle();
        await assert.equal(pageTitle, "JS30: 01 Drums");
      }
    )
    test.after(async function() { await driver.quit()});
  });
