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
        text: 'Getting Started'
      },
      {
        text: 'API',
        items: [
          { text: 'Queueable', link: '/api/queueable' },
          { text: 'Batchable', link: '/api/batchable' },
          { text: 'Schedulable', link: '/api/schedulable' }
        ]
      },
      {
        text: 'Examples',
        items: [
          { text: 'Queueable', link: '/examples/queueable' },
          { text: 'Batchable', link: '/examples/batchable' },
          { text: 'Schedulable', link: '/examples/schedulable' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/vuejs/vitepress' }
    ]
  }
})
