const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    setupFiles: [...(jestConfig.setupFiles || []), '<rootDir>/jest-setup.js'],
    moduleNameMapper: {
        '^lightning/modal$': '<rootDir>/dev/jest-mocks/lightning/modal',
        '^c/asyncBadgeStyles$':
            '<rootDir>/force-app/main/default/lwc/asyncBadgeStyles/asyncBadgeStyles.css'
    },
    testPathIgnorePatterns: [
        '<rootDir>/node_modules/',
        '<rootDir>/website/',
        '<rootDir>/ticket/',
        '/__tests__/data/'
    ]
};
