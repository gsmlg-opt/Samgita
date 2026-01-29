defmodule Samgita.Agent.Types do
  @moduledoc """
  Defines the 37 agent types organized by swarm.
  """

  @engineering [
    {"eng-frontend", "Frontend Engineer", "UI/UX implementation, React/Vue/HTML/CSS"},
    {"eng-backend", "Backend Engineer", "Server-side logic, APIs, business rules"},
    {"eng-database", "Database Engineer", "Schema design, migrations, queries, optimization"},
    {"eng-mobile", "Mobile Engineer", "iOS/Android/React Native development"},
    {"eng-api", "API Engineer", "API design, REST/GraphQL, documentation"},
    {"eng-qa", "QA Engineer", "Test writing, test automation, quality assurance"},
    {"eng-perf", "Performance Engineer", "Profiling, optimization, load testing"},
    {"eng-infra", "Infrastructure Engineer", "Cloud setup, networking, IaC"}
  ]

  @operations [
    {"ops-devops", "DevOps Engineer", "CI/CD pipelines, deployment automation"},
    {"ops-sre", "SRE", "Reliability, monitoring, incident response"},
    {"ops-security", "Security Engineer", "Security audits, vulnerability scanning"},
    {"ops-monitor", "Monitoring Engineer", "Observability, alerting, dashboards"},
    {"ops-incident", "Incident Manager", "Incident response, post-mortems"},
    {"ops-release", "Release Manager", "Release coordination, versioning"},
    {"ops-cost", "Cost Optimizer", "Cloud cost optimization, resource right-sizing"},
    {"ops-compliance", "Compliance Officer", "Regulatory compliance, auditing"}
  ]

  @business [
    {"biz-marketing", "Marketing Specialist", "Marketing strategy, content, campaigns"},
    {"biz-sales", "Sales Specialist", "Sales materials, pricing, outreach"},
    {"biz-finance", "Finance Analyst", "Financial modeling, budgets, forecasting"},
    {"biz-legal", "Legal Advisor", "Legal review, terms of service, privacy policy"},
    {"biz-support", "Support Specialist", "Help documentation, support workflows"},
    {"biz-hr", "HR Specialist", "Team structure, hiring, culture docs"},
    {"biz-investor", "Investor Relations", "Pitch decks, investor updates"},
    {"biz-partnerships", "Partnerships Manager", "Partner strategy, integrations"}
  ]

  @data [
    {"data-ml", "ML Engineer", "Machine learning models, training pipelines"},
    {"data-eng", "Data Engineer", "Data pipelines, ETL, data warehouse"},
    {"data-analytics", "Data Analyst", "Analytics, reporting, insights"}
  ]

  @product [
    {"prod-pm", "Product Manager", "Requirements, roadmap, prioritization"},
    {"prod-design", "Product Designer", "UX research, wireframes, design systems"},
    {"prod-techwriter", "Technical Writer", "Documentation, guides, API docs"}
  ]

  @growth [
    {"growth-hacker", "Growth Hacker", "Growth experiments, A/B testing, viral loops"},
    {"growth-community", "Community Manager", "Community building, engagement"},
    {"growth-success", "Customer Success", "Onboarding, retention, NPS"},
    {"growth-lifecycle", "Lifecycle Manager", "User journey, email sequences, churn"}
  ]

  @review [
    {"review-code", "Code Reviewer", "Code quality, best practices, architecture review"},
    {"review-business", "Business Reviewer", "Business model, strategy review"},
    {"review-security", "Security Reviewer", "Security review, threat modeling"}
  ]

  @all_types @engineering ++ @operations ++ @business ++ @data ++ @product ++ @growth ++ @review

  def all, do: @all_types
  def engineering, do: @engineering
  def operations, do: @operations
  def business, do: @business
  def data, do: @data
  def product, do: @product
  def growth, do: @growth
  def review, do: @review

  def all_ids, do: Enum.map(@all_types, &elem(&1, 0))

  def get(type_id) do
    Enum.find(@all_types, fn {id, _, _} -> id == type_id end)
  end

  def valid?(type_id), do: type_id in all_ids()

  def model_for_type(type_id) do
    cond do
      type_id in ["prod-pm", "eng-infra"] -> "opus"
      type_id in ["eng-qa", "ops-monitor", "review-code"] -> "haiku"
      true -> "sonnet"
    end
  end
end
