import os
import time
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DSN = (
    f"host={os.environ['DB_HOST']} dbname={os.environ['POSTGRES_DB']} "
    f"user={os.environ['POSTGRES_USER']} password={os.environ['POSTGRES_PASSWORD']}"
)


def conn():
    return psycopg.connect(DSN, connect_timeout=2)


@asynccontextmanager
async def lifespan(app: FastAPI):
    for _ in range(30):
        try:
            with conn() as c:
                c.execute(
                    "CREATE TABLE IF NOT EXISTS biljeske ("
                    "id SERIAL PRIMARY KEY, tekst TEXT NOT NULL, "
                    "kreirano TIMESTAMPTZ DEFAULT now())"
                )
            break
        except Exception:
            time.sleep(1)
    yield


app = FastAPI(lifespan=lifespan)


class Biljeska(BaseModel):
    tekst: str


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/ready")
def ready():
    try:
        with conn() as c:
            c.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="baza nedostupna")


@app.get("/api/notes")
def lista():
    with conn() as c:
        rows = c.execute(
            "SELECT id, tekst, kreirano FROM biljeske ORDER BY id DESC"
        ).fetchall()
    return [{"id": r[0], "tekst": r[1], "kreirano": r[2].isoformat()} for r in rows]


@app.post("/api/notes", status_code=201)
def dodaj(b: Biljeska):
    with conn() as c:
        row = c.execute(
            "INSERT INTO biljeske (tekst) VALUES (%s) RETURNING id", (b.tekst,)
        ).fetchone()
    return {"id": row[0]}


@app.delete("/api/notes/{note_id}")
def obrisi(note_id: int):
    with conn() as c:
        c.execute("DELETE FROM biljeske WHERE id = %s", (note_id,))
    return {"obrisano": note_id}
