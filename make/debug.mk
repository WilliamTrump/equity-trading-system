.PHONY: bounce-api

## ==========================================
# 🕵️ DOWNWARD API & ENV DEBUGGING
# ==========================================

bounce-api: ## 3. Force a graceful restart of the FastAPI pods to pick up new Env Vars
	@echo "🔄 Forcing a rolling restart of the FastAPI deployment..."
	@$(DOCKER) exec k8s-toolbox kubectl rollout restart deployment/fastapi-api -n backend
