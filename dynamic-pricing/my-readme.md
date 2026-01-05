- docker compose for /pricing service and redis(with ui)
- batch for the background bulk fetch from the /pricing service to minimize the api calls
    - bulk push to redis
- redis integration for caching
    - Built-in health monitoring and connection testing
- Upstream service(pricing service) monitoring and fallback
    - if service recovers after the trouble the app detects itself and make bulk fetch to protect api quota
- SQLite for historical data (to failover the redis failure) (configurable fresh period )
- coalescing for multi-same request to api to avoid calls multiple time at a instance of time (if redis and db fails)
- all configurable values in env specific
- test cases

 
flow diagram![alt text](image.png)