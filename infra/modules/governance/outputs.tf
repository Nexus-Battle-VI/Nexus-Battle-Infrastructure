output "budget_names" {
  value = [aws_budgets_budget.ceiling.name, aws_budgets_budget.operational.name]
}
