---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Async Lib"
  text: "Salesforce Apex Async Framework"
  tagline: Eliminate queueable limits, unify async processing, and build resilient job chains with elegant error handling
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: View Examples
      link: /getting-started

features:
  - title: Smart Queueable Jobs
    details: Automatically handles "Too many queueable jobs" errors through intelligent chaining and batch overflow. Features priority-based execution, sophisticated error handling, and powerful finalizers for cleanup logic.
    link: /api/queueable
  - title: Unified Batch Processing  
    details: Execute batch jobs immediately or schedule them for later with configurable scope sizes. Convert any batch job to schedulable with a single method call. Built-in error handling and result tracking.
    link: /api/batchable
  - title: Flexible Scheduling
    details: Intuitive CronBuilder for complex scheduling patterns. Convert queueable or batch jobs to schedulable effortlessly. Support for business hours, recurring intervals, and custom cron expressions.
    link: /api/schedulable
---

