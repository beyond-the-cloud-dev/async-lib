import { h } from 'vue';
import DefaultTheme from 'vitepress/theme';
import BTCFooter from './components/BTCFooter.vue';
import './custom.css';

export default {
    extends: DefaultTheme,
    Layout() {
        return h(DefaultTheme.Layout, null, {
            'layout-bottom': () => h(BTCFooter, { context: 'async-lib' })
        });
    },
    enhanceApp({ app }) {
        app.component('BTCFooter', BTCFooter);
    }
};
