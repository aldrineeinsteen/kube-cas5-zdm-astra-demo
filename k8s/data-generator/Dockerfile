FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the data generator script
COPY data_generator.py .

# Make script executable
RUN chmod +x data_generator.py

# Run the data generator
CMD ["python", "data_generator.py"]