from fastapi import FastAPI

app = FastAPI(title="Dummy API")


@app.get("/")
def dummy():
    return ("Hello from equity-trading-system",)
