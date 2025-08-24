import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "Async Lib",
  description: "Async Lib Documentation",
  cleanUrls: true,
  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Docs', link: '/getting-started' }
    ],

    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Getting Started', link: '/getting-started' }
        ]
      },
      {
        text: 'API',
        items: [
          { text: 'Queueable', link: '/api/queueable' },
          { text: 'Batchable', link: '/api/batchable' },
          { text: 'Schedulable', link: '/api/schedulable' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/beyond-the-cloud-dev/async-lib' },
      { icon: 'linkedin', link: 'https://www.linkedin.com/company/beyondtheclouddev' }

    ]
  }
})
