defmodule SamgitaWeb.AgentsLive.Index do
  use SamgitaWeb, :live_view

  @agent_types %{
    "Engineering Swarm" => [
      %{
        name: "eng-frontend",
        description: "Frontend development, UI/UX implementation",
        capabilities: [
          "React, Vue, Svelte, Next.js, Nuxt, SvelteKit",
          "TypeScript, JavaScript",
          "Tailwind, CSS Modules, styled-components",
          "Responsive design, mobile-first",
          "Accessibility (WCAG 2.1 AA)",
          "Performance optimization (Core Web Vitals)"
        ],
        task_types: [
          "ui-component",
          "page-layout",
          "styling",
          "accessibility-fix",
          "frontend-perf"
        ],
        quality_checks: [
          "Lighthouse score > 90",
          "No console errors",
          "Cross-browser testing (Chrome, Firefox, Safari)",
          "Mobile responsive verification"
        ]
      },
      %{
        name: "eng-backend",
        description: "Backend services, API development",
        capabilities: [
          "Node.js, Python, Go, Rust, Java",
          "REST API, GraphQL, gRPC",
          "Database design and optimization",
          "Caching (Redis, Memcached)",
          "Message queues (RabbitMQ, SQS, Kafka)"
        ],
        task_types: ["api-endpoint", "service", "integration", "business-logic"],
        quality_checks: [
          "API response < 100ms p99",
          "Input validation on all endpoints",
          "Error handling with proper status codes",
          "Rate limiting implemented"
        ]
      },
      %{
        name: "eng-database",
        description: "Database design, optimization, migrations",
        capabilities: [
          "PostgreSQL, MySQL, MongoDB, Redis",
          "Schema design, normalization",
          "Migrations (Prisma, Drizzle, Knex, Alembic)",
          "Query optimization, indexing",
          "Replication, sharding strategies",
          "Backup and recovery"
        ],
        task_types: ["schema-design", "migration", "query-optimize", "index", "data-seed"],
        quality_checks: [
          "No N+1 queries",
          "All queries use indexes (EXPLAIN ANALYZE)",
          "Migrations are reversible",
          "Foreign keys enforced"
        ]
      },
      %{
        name: "eng-mobile",
        description: "Mobile app development (iOS/Android)",
        capabilities: [
          "React Native, Flutter, Swift, Kotlin",
          "Cross-platform strategies",
          "Native modules, platform-specific code",
          "Push notifications",
          "Offline-first, local storage",
          "App store deployment"
        ],
        task_types: [
          "mobile-screen",
          "native-feature",
          "offline-sync",
          "push-notification",
          "app-store"
        ],
        quality_checks: [
          "60fps smooth scrolling",
          "App size < 50MB",
          "Cold start < 3s",
          "Memory efficient"
        ]
      },
      %{
        name: "eng-api",
        description: "API design, documentation, versioning",
        capabilities: [
          "OpenAPI/Swagger specification",
          "API versioning strategies",
          "SDK generation",
          "Rate limiting design",
          "Webhook systems",
          "API documentation"
        ],
        task_types: ["api-spec", "sdk-generate", "webhook", "api-docs", "versioning"],
        quality_checks: [
          "100% endpoint documentation",
          "All errors have consistent format",
          "SDK tests pass",
          "Postman collection updated"
        ]
      },
      %{
        name: "eng-qa",
        description: "Quality assurance, test automation",
        capabilities: [
          "Unit testing (Jest, pytest, Go test)",
          "Integration testing",
          "E2E testing (Playwright, Cypress)",
          "Load testing (k6, Artillery)",
          "Fuzz testing",
          "Test automation"
        ],
        task_types: ["unit-test", "integration-test", "e2e-test", "load-test", "test-coverage"],
        quality_checks: [
          "Coverage > 80%",
          "All critical paths tested",
          "No flaky tests",
          "CI passes consistently"
        ]
      },
      %{
        name: "eng-perf",
        description: "Performance optimization, profiling",
        capabilities: [
          "Application profiling (CPU, memory, I/O)",
          "Performance benchmarking",
          "Bottleneck identification",
          "Caching strategy (Redis, CDN, in-memory)",
          "Database query optimization",
          "Bundle size optimization",
          "Core Web Vitals optimization"
        ],
        task_types: ["profile", "benchmark", "optimize", "cache-strategy", "bundle-optimize"],
        quality_checks: [
          "p99 latency < target",
          "Memory usage stable (no leaks)",
          "Benchmarks documented and reproducible",
          "Before/after metrics recorded"
        ]
      },
      %{
        name: "eng-infra",
        description: "Infrastructure, CI/CD, tooling",
        capabilities: [
          "Dockerfile creation and optimization",
          "Kubernetes manifest review",
          "Helm chart development",
          "Infrastructure as Code review",
          "Container security",
          "Multi-stage builds",
          "Resource limits and requests"
        ],
        task_types: [
          "dockerfile",
          "k8s-manifest",
          "helm-chart",
          "iac-review",
          "container-security"
        ],
        quality_checks: [
          "Images use minimal base",
          "No secrets in images",
          "Resource limits set",
          "Health checks defined"
        ]
      }
    ],
    "Operations Swarm" => [
      %{
        name: "ops-devops",
        description: "DevOps practices, automation",
        capabilities: [
          "CI/CD (GitHub Actions, GitLab CI, Jenkins)",
          "Infrastructure as Code (Terraform, Pulumi, CDK)",
          "Container orchestration (Docker, Kubernetes)",
          "Cloud platforms (AWS, GCP, Azure)",
          "GitOps (ArgoCD, Flux)"
        ],
        task_types: ["ci-pipeline", "cd-pipeline", "infrastructure", "container", "k8s"],
        quality_checks: [
          "Pipeline runs < 10min",
          "Zero-downtime deployments",
          "Infrastructure is reproducible",
          "Secrets properly managed"
        ]
      },
      %{
        name: "ops-sre",
        description: "Site reliability engineering",
        capabilities: [
          "Site Reliability Engineering",
          "SLO/SLI/SLA definition",
          "Error budgets",
          "Capacity planning",
          "Chaos engineering",
          "Toil reduction",
          "On-call procedures"
        ],
        task_types: ["slo-define", "error-budget", "capacity-plan", "chaos-test", "toil-reduce"],
        quality_checks: [
          "SLOs documented and measured",
          "Error budget not exhausted",
          "Capacity headroom > 30%",
          "Chaos tests pass"
        ]
      },
      %{
        name: "ops-security",
        description: "Security audits, vulnerability management",
        capabilities: [
          "SAST (static analysis)",
          "DAST (dynamic analysis)",
          "Dependency scanning",
          "Container scanning",
          "Penetration testing",
          "Compliance (SOC2, GDPR, HIPAA)"
        ],
        task_types: [
          "security-scan",
          "vulnerability-fix",
          "penetration-test",
          "compliance-check",
          "security-policy"
        ],
        quality_checks: [
          "Zero high/critical vulnerabilities",
          "All secrets in vault",
          "HTTPS everywhere",
          "Input sanitization verified"
        ]
      },
      %{
        name: "ops-monitor",
        description: "Monitoring, alerting, observability",
        capabilities: [
          "Observability (Datadog, New Relic, Grafana)",
          "Logging (ELK, Loki)",
          "Tracing (Jaeger, Zipkin)",
          "Alerting rules",
          "SLO/SLI definition",
          "Dashboards"
        ],
        task_types: ["monitoring-setup", "dashboard", "alert-rule", "log-pipeline", "tracing"],
        quality_checks: [
          "All services have health checks",
          "Critical paths have alerts",
          "Logs are structured JSON",
          "Traces cover full request lifecycle"
        ]
      },
      %{
        name: "ops-incident",
        description: "Incident response, postmortems",
        capabilities: [
          "Incident detection",
          "Runbook creation",
          "Auto-remediation scripts",
          "Root cause analysis",
          "Post-mortem documentation",
          "On-call management"
        ],
        task_types: ["runbook", "auto-remediation", "incident-response", "rca", "postmortem"],
        quality_checks: [
          "MTTR < 30min for P1",
          "All incidents have RCA",
          "Runbooks are tested",
          "Auto-remediation success > 80%"
        ]
      },
      %{
        name: "ops-release",
        description: "Release management, deployment",
        capabilities: [
          "Semantic versioning",
          "Changelog generation",
          "Release notes",
          "Feature flags",
          "Blue-green deployments",
          "Canary releases",
          "Rollback procedures"
        ],
        task_types: ["version-bump", "changelog", "feature-flag", "canary", "rollback"],
        quality_checks: [
          "All releases tagged",
          "Changelog accurate",
          "Rollback tested",
          "Feature flags documented"
        ]
      },
      %{
        name: "ops-cost",
        description: "Cost optimization, resource management",
        capabilities: [
          "Cloud cost analysis",
          "Resource right-sizing",
          "Reserved instance planning",
          "Spot instance strategies",
          "Cost allocation tags",
          "Budget alerts"
        ],
        task_types: [
          "cost-analysis",
          "right-size",
          "spot-strategy",
          "budget-alert",
          "cost-report"
        ],
        quality_checks: [
          "Monthly cost within budget",
          "No unused resources",
          "All resources tagged",
          "Cost per user tracked"
        ]
      },
      %{
        name: "ops-compliance",
        description: "Compliance, auditing, governance",
        capabilities: [
          "SOC 2 Type II preparation",
          "GDPR compliance",
          "HIPAA compliance",
          "PCI-DSS compliance",
          "ISO 27001",
          "Audit preparation",
          "Policy documentation"
        ],
        task_types: [
          "compliance-assess",
          "policy-write",
          "control-implement",
          "audit-prep",
          "evidence-collect"
        ],
        quality_checks: [
          "All required policies documented",
          "Controls implemented and tested",
          "Evidence organized and accessible",
          "Audit findings addressed"
        ]
      }
    ],
    "Business Swarm" => [
      %{
        name: "biz-marketing",
        description: "Marketing strategy, campaigns",
        capabilities: [
          "Landing page copy",
          "SEO optimization",
          "Content marketing",
          "Email campaigns",
          "Social media content",
          "Analytics tracking"
        ],
        task_types: ["landing-page", "seo", "blog-post", "email-campaign", "social-content"],
        quality_checks: [
          "Core Web Vitals pass",
          "Meta tags complete",
          "Analytics tracking verified",
          "A/B tests running"
        ]
      },
      %{
        name: "biz-sales",
        description: "Sales strategy, customer acquisition",
        capabilities: [
          "CRM setup (HubSpot, Salesforce)",
          "Sales pipeline design",
          "Outreach templates",
          "Demo scripts",
          "Proposal generation",
          "Contract management"
        ],
        task_types: ["crm-setup", "outreach", "demo-script", "proposal", "pipeline"],
        quality_checks: [
          "CRM data clean",
          "Follow-up automation working",
          "Proposals branded correctly",
          "Pipeline stages defined"
        ]
      },
      %{
        name: "biz-finance",
        description: "Financial planning, budgeting",
        capabilities: [
          "Billing system setup (Stripe, Paddle)",
          "Invoice generation",
          "Revenue recognition",
          "Runway calculation",
          "Financial reporting",
          "Pricing strategy"
        ],
        task_types: ["billing-setup", "pricing", "invoice", "financial-report", "runway"],
        quality_checks: [
          "PCI compliance",
          "Invoices accurate",
          "Metrics tracked (MRR, ARR, churn)",
          "Runway > 6 months"
        ]
      },
      %{
        name: "biz-legal",
        description: "Legal compliance, contracts",
        capabilities: [
          "Terms of Service",
          "Privacy Policy",
          "Cookie Policy",
          "GDPR compliance",
          "Contract templates",
          "IP protection"
        ],
        task_types: ["tos", "privacy-policy", "gdpr", "contract", "compliance"],
        quality_checks: [
          "All policies published",
          "Cookie consent implemented",
          "Data deletion capability",
          "Contracts reviewed"
        ]
      },
      %{
        name: "biz-support",
        description: "Customer support, documentation",
        capabilities: [
          "Help documentation",
          "FAQ creation",
          "Chatbot setup",
          "Ticket system",
          "Knowledge base",
          "User onboarding"
        ],
        task_types: ["help-docs", "faq", "chatbot", "ticket-system", "onboarding"],
        quality_checks: [
          "All features documented",
          "FAQ covers common questions",
          "Response time < 4h",
          "Onboarding completion > 80%"
        ]
      },
      %{
        name: "biz-hr",
        description: "HR policies, team culture",
        capabilities: [
          "Job description writing",
          "Recruiting pipeline setup",
          "Interview process design",
          "Onboarding documentation",
          "Culture documentation",
          "Employee handbook",
          "Performance review templates"
        ],
        task_types: [
          "job-post",
          "recruiting-setup",
          "interview-design",
          "onboarding-docs",
          "culture-docs"
        ],
        quality_checks: [
          "Job posts are inclusive and clear",
          "Interview process documented",
          "Onboarding covers all essentials",
          "Policies are compliant"
        ]
      },
      %{
        name: "biz-investor",
        description: "Investor relations, fundraising",
        capabilities: [
          "Pitch deck creation",
          "Investor update emails",
          "Data room preparation",
          "Cap table management",
          "Financial modeling",
          "Due diligence preparation",
          "Term sheet review"
        ],
        task_types: ["pitch-deck", "investor-update", "data-room", "financial-model", "dd-prep"],
        quality_checks: [
          "Metrics accurate and sourced",
          "Narrative compelling and clear",
          "Data room organized",
          "Financials reconciled"
        ]
      },
      %{
        name: "biz-partnerships",
        description: "Strategic partnerships, alliances",
        capabilities: [
          "Partnership outreach",
          "Integration partnerships",
          "Co-marketing agreements",
          "Channel partnerships",
          "API partnership programs",
          "Partner documentation",
          "Revenue sharing models"
        ],
        task_types: [
          "partner-outreach",
          "integration-partner",
          "co-marketing",
          "partner-docs",
          "partner-program"
        ],
        quality_checks: [
          "Partners aligned with strategy",
          "Agreements documented",
          "Integration tested",
          "ROI tracked"
        ]
      }
    ],
    "Data Swarm" => [
      %{
        name: "data-ml",
        description: "Machine learning, model training",
        capabilities: [
          "Machine learning model development",
          "MLOps and model deployment",
          "Feature engineering",
          "Model training and tuning",
          "A/B testing for ML models",
          "Model monitoring",
          "LLM integration and prompting"
        ],
        task_types: [
          "model-train",
          "model-deploy",
          "feature-eng",
          "model-monitor",
          "llm-integrate"
        ],
        quality_checks: [
          "Model performance meets threshold",
          "Training reproducible",
          "Model versioned",
          "Monitoring alerts configured"
        ]
      },
      %{
        name: "data-eng",
        description: "Data engineering, ETL pipelines",
        capabilities: [
          "ETL pipeline development",
          "Data warehousing (Snowflake, BigQuery, Redshift)",
          "dbt transformations",
          "Airflow/Dagster orchestration",
          "Data quality checks",
          "Schema design",
          "Data governance"
        ],
        task_types: [
          "etl-pipeline",
          "dbt-model",
          "data-quality",
          "warehouse-design",
          "pipeline-monitor"
        ],
        quality_checks: [
          "Pipelines idempotent",
          "Data freshness SLA met",
          "Quality checks passing",
          "Documentation complete"
        ]
      },
      %{
        name: "data-analytics",
        description: "Analytics, reporting, insights",
        capabilities: [
          "Business intelligence",
          "Dashboard creation (Metabase, Looker, Tableau)",
          "SQL analysis",
          "Metrics definition",
          "Self-serve analytics",
          "Data storytelling"
        ],
        task_types: ["dashboard", "metrics-define", "analysis", "self-serve", "report"],
        quality_checks: [
          "Metrics clearly defined",
          "Dashboards performant",
          "Data accurate",
          "Insights actionable"
        ]
      }
    ],
    "Product Swarm" => [
      %{
        name: "prod-pm",
        description: "Product management, roadmap",
        capabilities: [
          "Product requirements documentation",
          "User story writing",
          "Backlog grooming and prioritization",
          "Roadmap planning",
          "Feature specifications",
          "Stakeholder communication",
          "Competitive analysis"
        ],
        task_types: ["prd-write", "user-story", "backlog-groom", "roadmap", "spec"],
        quality_checks: [
          "Requirements clear and testable",
          "Acceptance criteria defined",
          "Priorities justified",
          "Stakeholders aligned"
        ]
      },
      %{
        name: "prod-design",
        description: "Product design, user research",
        capabilities: [
          "Design system creation",
          "UI/UX patterns",
          "Figma prototyping",
          "Accessibility design",
          "User research synthesis",
          "Design documentation",
          "Component library"
        ],
        task_types: ["design-system", "prototype", "ux-pattern", "accessibility", "component"],
        quality_checks: [
          "Design system consistent",
          "Prototypes tested",
          "WCAG compliant",
          "Components documented"
        ]
      },
      %{
        name: "prod-techwriter",
        description: "Technical writing, documentation",
        capabilities: [
          "API documentation",
          "User guides and tutorials",
          "Release notes",
          "README files",
          "Architecture documentation",
          "Runbooks",
          "Knowledge base articles"
        ],
        task_types: ["api-docs", "user-guide", "release-notes", "tutorial", "architecture-doc"],
        quality_checks: [
          "Documentation accurate",
          "Examples work",
          "Searchable and organized",
          "Up to date with code"
        ]
      }
    ],
    "Growth Swarm" => [
      %{
        name: "growth-hacker",
        description: "Growth experiments, viral loops",
        capabilities: [
          "Growth experiment design",
          "Viral loop optimization",
          "Referral program design",
          "Activation optimization",
          "Retention strategies",
          "Churn prediction",
          "PLG (Product-Led Growth) tactics"
        ],
        task_types: [
          "growth-experiment",
          "viral-loop",
          "referral-program",
          "activation",
          "retention"
        ],
        quality_checks: [
          "Experiments statistically valid",
          "Metrics tracked",
          "Results documented",
          "Winners implemented"
        ]
      },
      %{
        name: "growth-community",
        description: "Community building, engagement",
        capabilities: [
          "Community building",
          "Discord/Slack community management",
          "User-generated content programs",
          "Ambassador programs",
          "Community events",
          "Feedback collection",
          "Community analytics"
        ],
        task_types: ["community-setup", "ambassador", "event", "ugc", "feedback-loop"],
        quality_checks: [
          "Community guidelines published",
          "Engagement metrics tracked",
          "Feedback actioned",
          "Community health monitored"
        ]
      },
      %{
        name: "growth-success",
        description: "Customer success, onboarding",
        capabilities: [
          "Customer success workflows",
          "Health scoring",
          "Churn prevention",
          "Expansion revenue",
          "QBR (Quarterly Business Review)",
          "Customer journey mapping",
          "NPS and CSAT programs"
        ],
        task_types: ["health-score", "churn-prevent", "expansion", "qbr", "nps"],
        quality_checks: [
          "Health scores calibrated",
          "At-risk accounts identified",
          "NRR (Net Revenue Retention) tracked",
          "Customer feedback actioned"
        ]
      },
      %{
        name: "growth-lifecycle",
        description: "User lifecycle, retention",
        capabilities: [
          "Email lifecycle marketing",
          "In-app messaging",
          "Push notification strategy",
          "Behavioral triggers",
          "Segmentation",
          "Personalization",
          "Re-engagement campaigns"
        ],
        task_types: ["lifecycle-email", "in-app", "push", "segment", "re-engage"],
        quality_checks: [
          "Messages personalized",
          "Triggers tested",
          "Opt-out working",
          "Performance tracked"
        ]
      }
    ],
    "Review Swarm" => [
      %{
        name: "review-code",
        description: "Code review, quality gates",
        capabilities: [
          "Code quality assessment",
          "Design pattern recognition",
          "SOLID principles verification",
          "Code smell detection",
          "Maintainability scoring",
          "Duplication detection",
          "Complexity analysis"
        ],
        task_types: ["review-code", "review-pr", "review-refactor"],
        quality_checks: [
          "Issues documented with severity",
          "Suggestions actionable",
          "Assessment clear (PASS/FAIL)",
          "Strengths identified"
        ],
        model: "opus"
      },
      %{
        name: "review-business",
        description: "Business logic review",
        capabilities: [
          "Requirements alignment verification",
          "Business logic correctness",
          "Edge case identification",
          "User flow validation",
          "Acceptance criteria checking",
          "Domain model accuracy"
        ],
        task_types: ["review-business", "review-requirements", "review-edge-cases"],
        quality_checks: [
          "Implementation matches PRD",
          "Acceptance criteria met",
          "Edge cases handled",
          "Domain logic correct"
        ],
        model: "opus"
      },
      %{
        name: "review-security",
        description: "Security review, threat modeling",
        capabilities: [
          "Vulnerability detection",
          "Authentication review",
          "Authorization verification",
          "Input validation checking",
          "Secret exposure detection",
          "Dependency vulnerability scanning",
          "OWASP Top 10 checking"
        ],
        task_types: ["review-security", "review-auth", "review-input"],
        quality_checks: [
          "No hardcoded secrets",
          "No SQL injection vulnerabilities",
          "No XSS vulnerabilities",
          "Authentication/authorization verified"
        ],
        model: "opus"
      }
    ]
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Agent Definitions",
       agent_types: @agent_types,
       selected_swarm: nil,
       expanded_agents: MapSet.new()
     )}
  end

  @impl true
  def handle_event("select_swarm", %{"swarm" => swarm}, socket) do
    {:noreply, assign(socket, selected_swarm: swarm, expanded_agents: MapSet.new())}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_swarm: nil, expanded_agents: MapSet.new())}
  end

  @impl true
  def handle_event("toggle_agent", %{"agent" => agent_name}, socket) do
    expanded_agents =
      if MapSet.member?(socket.assigns.expanded_agents, agent_name) do
        MapSet.delete(socket.assigns.expanded_agents, agent_name)
      else
        MapSet.put(socket.assigns.expanded_agents, agent_name)
      end

    {:noreply, assign(socket, expanded_agents: expanded_agents)}
  end

  def is_expanded?(expanded_agents, agent_name) do
    MapSet.member?(expanded_agents, agent_name)
  end

  def agent_markdown(agent, swarm_name) do
    """
    ### #{agent.name}

    **Description:** #{agent.description}

    **Capabilities:**
    #{Enum.map_join(agent.capabilities, "\n", &"- #{&1}")}

    **Task Types:**
    #{Enum.map_join(agent.task_types, "\n", &"- `#{&1}`")}

    **Quality Checks:**
    #{Enum.map_join(agent.quality_checks, "\n", &"- #{&1}")}
    #{if Map.get(agent, :model), do: "\n**Recommended Model:** `#{Map.get(agent, :model)}` (required for deep analysis)", else: ""}

    **Swarm:** #{swarm_name}
    """
  end

  def swarm_color("Engineering Swarm"), do: "bg-blue-100 border-blue-300 text-blue-800"
  def swarm_color("Operations Swarm"), do: "bg-green-100 border-green-300 text-green-800"
  def swarm_color("Business Swarm"), do: "bg-purple-100 border-purple-300 text-purple-800"
  def swarm_color("Data Swarm"), do: "bg-orange-100 border-orange-300 text-orange-800"
  def swarm_color("Product Swarm"), do: "bg-pink-100 border-pink-300 text-pink-800"
  def swarm_color("Growth Swarm"), do: "bg-yellow-100 border-yellow-300 text-yellow-800"
  def swarm_color("Review Swarm"), do: "bg-red-100 border-red-300 text-red-800"
  def swarm_color(_), do: "bg-zinc-100 border-zinc-300 text-zinc-800"
end
