import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db.models import Base
from hypothesis import settings, HealthCheck

settings.register_profile("echosync", max_examples=100, suppress_health_check=[HealthCheck.too_slow, HealthCheck.function_scoped_fixture])
settings.load_profile("echosync")

@pytest.fixture(name="db_session")
def fixture_db_session():
    # Use in-memory SQLite for testing
    engine = create_engine("sqlite:///:memory:")
    
    # Enable SQLite foreign keys on in-memory db
    from sqlalchemy import event
    from sqlalchemy.engine import Engine
    @event.listens_for(Engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
        
    Base.metadata.create_all(bind=engine)
    SessionLocalTest = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    session = SessionLocalTest()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)
