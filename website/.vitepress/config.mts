import { defineConfig } from 'vitepress';

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: 'Async Lib',
  description: 'Async Lib Documentation',
  head: [
    ['link', { rel: 'icon', href: '/favicon.ico' }],
    [
      'script',
      {
        async: '',
        src: 'https://www.googletagmanager.com/gtag/js?id=G-53N22KN47H'
      }
    ],
    [
      'script',
      {},
      `window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-53N22KN47H');`
    ]
  ],
  sitemap: {
    hostname: 'https://async.beyondthecloud.dev'
  },
  themeConfig: {
    logo: '/logo.png',
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Docs', link: '/getting-started' }
    ],

    sidebar: [
      {
        text: 'Introduction',
        collapsed: false,
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
      },
      {
        text: 'Explanations',
        collapsed: false,
        items: [
          {
            text: 'Initial Queueable Chain Schedulable',
            link: '/explanations/initial-scheduled-queuable-batch-job'
          },
          { text: 'Job Cloning', link: '/explanations/job-cloning' }
        ]
      }
    ],
    footer: false,
    socialLinks: [
      {
        icon: 'github',
        link: 'https://github.com/beyond-the-cloud-dev/async-lib'
      },
      {
        icon: 'linkedin',
        link: 'https://www.linkedin.com/company/beyondtheclouddev'
      }
    ]
  }
});
