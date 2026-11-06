// jsdom's CSS parser predates @container, so it logs an error for the sequence stylesheet on
// every mount. The browser is where that rule is tested; the tests do not read styles.
const jsdomCssNoise = /Could not parse CSS stylesheet/;
const originalError = console.error;
console.error = (...args) => {
    if (args.some(arg => jsdomCssNoise.test(arg?.message || String(arg)))) return;
    originalError(...args);
};
