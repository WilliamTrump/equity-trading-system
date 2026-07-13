.PHONY: db-backup db-restore psql redis-cli redis-sentinel adminer-info

# ==========================================
# 💾 DATABASE OPERATIONS
# ==========================================

adminer-info: ## 🌐 Adminer UI: http://adminer.localhost:8080
	@echo "🌐 Adminer UI: http://adminer.localhost:8080"
	@echo "🔍 Fetching Postgres Credentials from cluster..."
	@echo -n "User: "
	@$(DOCKER) exec k8s-toolbox kubectl get secret db-credentials -n data -o jsonpath='{.data.POSTGRES_USER}' | base64 -d; echo ""
	@echo -n "Pass: "
	@$(DOCKER) exec k8s-toolbox kubectl get secret db-credentials -n data -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo ""

psql: ## 🐘 Starting interactive PostgreSQL session...
	@echo "🐘 Starting interactive PostgreSQL session..."
	@$(DOCKER) exec -it k8s-toolbox bash -c 'POD=$$(kubectl get pods -n data -l "cnpg.io/cluster=trading-db,cnpg.io/instanceRole=primary" -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $$POD -n data -- psql -U trade_admin -d trading'

redis-cli: ## 🔴 Connecting to Redis CLI dynamically...
	@echo "🔴 Finding active Redis node and launching CLI..."
	@$(DOCKER) exec -it k8s-toolbox bash -c 'POD=$$(kubectl get pods -n data -l "app.kubernetes.io/name=redis" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || kubectl get pods -n data -l "app=redis" -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $$POD -n data -- redis-cli'

redis-sentinel: ## 🛡️ Connecting to Redis Sentinel CLI...
	@echo "🛡️ Connecting to Sentinel to check quorum..."
	@$(DOCKER) exec -it k8s-toolbox bash -c 'POD=$$(kubectl get pods -n data -l "app.kubernetes.io/name=redis,app.kubernetes.io/component=sentinel" -o jsonpath="{.items[0].metadata.name}"); kubectl exec -it $$POD -n data -- redis-cli -p 26379 info sentinel'

db-backup: ## 💾 Take a snapshot of the trading DB and save to project root
	@echo "💾 Taking snapshot of 'trading' database from primary node..."
	@$(DOCKER) exec -it k8s-toolbox bash -c '\
		POD=$$(kubectl get pods -n data -l "cnpg.io/cluster=trading-db,cnpg.io/instanceRole=primary" -o jsonpath="{.items[0].metadata.name}") && \
		echo "📦 Creating dump inside pod $$POD..." && \
		kubectl exec -n data $$POD -- pg_dump -U postgres -d trading -F c -f /dev/shm/trading_backup.dump && \
		echo "⬇️ Copying backup to host..." && \
		kubectl cp data/$$POD:/dev/shm/trading_backup.dump /workspace/trading_backup.dump \
	'
	@echo "✅ Backup successfully saved to ./trading_backup.dump!"

db-restore: ## ⚠️ RESTORE snapshot to the trading DB (Destructive)
	@echo "============================================="
	@echo "    ⚠️  DATABASE RESTORE MENU"
	@echo "============================================="
	@DUMPS=$$(ls *.dump 2>/dev/null); \
	if [ -z "$$DUMPS" ]; then \
		echo "❌ No .dump files found in the current directory!"; \
		exit 1; \
	fi; \
	PS3="Select a backup file to restore (or type a number to exit): "; \
	select file in $$DUMPS "Exit"; do \
		if [ "$$file" = "Exit" ]; then echo "Gracefully exiting."; break; fi; \
		if [ -n "$$file" ]; then \
			echo "⚠️  WARNING: This will drop and replace the current 'trading' database!"; \
			echo "⏳ Copying $$file into the primary pod and restoring..."; \
			$(DOCKER) exec -it k8s-toolbox bash -c '\
				POD=$$(kubectl get pods -n data -l "cnpg.io/cluster=trading-db,cnpg.io/instanceRole=primary" -o jsonpath="{.items[0].metadata.name}") && \
				echo "⬆️ Copying backup file into pod $$POD..." && \
				kubectl cp /workspace/'"$$file"' data/$$POD:/dev/shm/trading_backup.dump && \
				echo "🔥 Restoring database (with clean)..." && \
				kubectl exec -n data $$POD -- pg_restore -U postgres -d trading -c /dev/shm/trading_backup.dump \
			'; \
			echo "✅ Database restored successfully!"; \
			echo "♻️ Restarting dependent deployments to flush stale DB connections..."; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/trading-pooler -n data; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/trading-pooler-ro -n data; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/adminer -n data; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/fastapi-api -n backend; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/trade-writer -n backend; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/db-syncer -n backend; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/price-cacher -n backend; \
			$(DOCKER) exec -it k8s-toolbox kubectl rollout restart deployment/price-timeseries-cacher -n backend; \
			break; \
		fi; \
	done
