const lwcConfig = require('@salesforce/eslint-config-lwc');
const jestPlugin = require('eslint-plugin-jest');

module.exports = [
    ...lwcConfig.configs.recommended,
    {
        files: ['**/__tests__/**/*.js', 'dev/jest-mocks/**/*.js'],
        ...jestPlugin.configs['flat/recommended'],
        languageOptions: { globals: { ...jestPlugin.environments.globals.globals } }
    }
];
