FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
COPY requirements.txt requirements-vision.txt ./
RUN pip install --no-cache-dir -r requirements.txt
# Photo matching model (DINOv2-small, CPU). Baked into the image so searches never wait on a download.
RUN pip install --no-cache-dir -r requirements-vision.txt --extra-index-url https://download.pytorch.org/whl/cpu \
 && python -c "from transformers import AutoModel, AutoImageProcessor; AutoImageProcessor.from_pretrained('facebook/dinov2-small'); AutoModel.from_pretrained('facebook/dinov2-small')"
COPY app ./app

EXPOSE 8000
# Single worker on purpose: background search jobs live in-process.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--proxy-headers", "--forwarded-allow-ips", "*"]
