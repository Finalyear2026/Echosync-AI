from hypothesis import settings, HealthCheck

settings.register_profile("echosync", max_examples=100, suppress_health_check=[HealthCheck.too_slow])
settings.load_profile("echosync")
