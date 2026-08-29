import { defineConfig } from 'vitepress';
import llmstxt from 'vitepress-plugin-llms';

// https://vitepress.dev/reference/site-config

const siteUrl = 'https://async.beyondthecloud.dev';
const siteTitle = 'Async Lib';
const siteDescription =
  'Open-source Apex library for managing asynchronous processes in Salesforce. Fluent API for Queueable, Batchable and Schedulable jobs, with job chaining, cloning and mocking of async jobs in unit tests. Free, MIT licensed, part of Apex Fluently by Beyond The Cloud.';

export default defineConfig({
  lang: 'en-US',
  title: siteTitle,
  description: siteDescription,
  cleanUrls: true,
  head: [
    ['link', { rel: 'icon', href: '/favicon.ico' }],
    ['meta', { name: 'author', content: 'Beyond The Cloud' }],
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:site_name', content: siteTitle }],
    ['meta', { property: 'og:image', content: `${siteUrl}/logo.png` }],
    ['meta', { name: 'twitter:card', content: 'summary' }],
    [
      'script',
      { type: 'application/ld+json' },
      JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'SoftwareApplication',
        name: siteTitle,
        description: siteDescription,
        url: siteUrl,
        applicationCategory: 'DeveloperApplication',
        operatingSystem: 'Salesforce',
        license: 'https://opensource.org/licenses/MIT',
        codeRepository: 'https://github.com/beyond-the-cloud-dev/async-lib',
        isPartOf: {
          '@type': 'SoftwareApplication',
          name: 'Apex Fluently',
          url: 'https://apexfluently.beyondthecloud.dev'
        },
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
        author: {
          '@type': 'Organization',
          name: 'Beyond The Cloud',
          url: 'https://beyondthecloud.dev',
          sameAs: [
            'https://github.com/beyond-the-cloud-dev',
            'https://www.linkedin.com/company/beyondtheclouddev'
          ]
        }
      })
    ],
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
    hostname: siteUrl
  },
  vite: {
    plugins: [llmstxt({ domain: siteUrl })]
  },
  transformPageData(pageData) {
    const canonicalUrl = `${siteUrl}/${pageData.relativePath}`
      .replace(/index\.md$/, '')
      .replace(/\.md$/, '')
      .replace(/\/$/, '');
    pageData.frontmatter.head ??= [];
    pageData.frontmatter.head.push(
      ['link', { rel: 'canonical', href: canonicalUrl || siteUrl }],
      ['meta', { property: 'og:url', content: canonicalUrl || siteUrl }]
    );
    const pageTitle = pageData.frontmatter.title || pageData.title;
    pageData.frontmatter.head.push(
      [
        'meta',
        {
          property: 'og:title',
          content:
            pageTitle && pageTitle !== siteTitle
              ? `${pageTitle} | ${siteTitle}`
              : siteTitle
        }
      ],
      [
        'meta',
        {
          property: 'og:description',
          content:
            pageData.frontmatter.description ||
            pageData.description ||
            siteDescription
        }
      ]
    );
  },
  themeConfig: {
    logo: '/logo.png',
    search: {
      provider: 'local'
    },
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
          {
            text: 'Standard Apex vs Async Lib',
            link: '/introduction/standard-apex-vs-async-lib'
          },
          { text: 'Installation', link: '/introduction/installation' }
        ]
      },
      {
        text: 'API',
        collapsed: false,
        items: [
          { text: 'Queueable', link: '/api/queueable' },
          { text: 'Chunk', link: '/api/chunk' },
          { text: 'Batchable', link: '/api/batchable' },
          { text: 'Schedulable', link: '/api/schedulable' },
          { text: 'AsyncMock', link: '/api/async-mock' }
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
          { text: 'Job Cloning', link: '/explanations/job-cloning' },
          {
            text: 'Deep Clone in Packages',
            link: '/explanations/deep-clone-in-packages'
          },
          { text: 'Testing Async Jobs', link: '/explanations/testing-async-jobs' },
          {
            text: 'AsyncResult Cleanup',
            link: '/explanations/asyncresult-cleanup'
          },
          {
            text: 'Expected Exceptions in Debug Logs',
            link: '/explanations/expected-exceptions-in-debug-logs'
          }
        ]
      }
    ],
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
