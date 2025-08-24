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
        collapsed: true,
        items: [
          { text: 'Getting Started', link: '/getting-started' },
          { text: 'Installation', link: '/introduction/installation' }
        ]
      },
      {
        text: 'API',
        collapsed: false,
        items: [
          { text: 'Queueable', link: '/api/queueable' },
          { text: 'Batchable', link: '/api/batchable' },
          { text: 'Schedulable', link: '/api/schedulable' }
        ]
      }
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025-present Beyond The Cloud Sp. z o.o.'
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/beyond-the-cloud-dev/async-lib' },
      { icon: 'linkedin', link: 'https://www.linkedin.com/company/beyondtheclouddev' }
    ]
  }
})
