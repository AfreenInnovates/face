from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
from statistics import mode
import tensorflow as tf
import base64
import os
import sys
import time  # <--- Added time for the delay logic
from dotenv import load_dotenv
from openai import OpenAI

# Load environment variables
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Add parent directory to path to import utils
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.inference import detect_faces, apply_offsets
from utils.inference import load_detection_model

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
detection_model_path = '../trained_models/detection_models/haarcascade_frontalface_default.xml'
emotion_model_path = '../trained_models/emotion_models/emotion_model_large_v2.tflite'
emotion_labels = ['angry', 'disgust', 'fear', 'happy', 'neutral', 'sad', 'surprise']

# --- LOAD MODELS ---
face_detection = load_detection_model(detection_model_path)

interpreter = tf.lite.Interpreter(model_path=emotion_model_path)
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()
emotion_target_size = (224, 224) 

frame_window = 10
emotion_offsets = (20, 40)
emotion_windows = {}

nebius_client = OpenAI(
    base_url="https://api.tokenfactory.nebius.com/v1/",
    api_key=os.environ.get("NEBIUS_API_KEY")
)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'})

@app.route('/detect_emotion', methods=['POST'])
def detect_emotion():
    try:
        data = request.json
        image_data = data.get('image')
        session_id = data.get('session_id', 'default')
        
        image_bytes = base64.b64decode(image_data.split(',')[1])
        nparr = np.frombuffer(image_bytes, np.uint8)
        bgr_image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if bgr_image is None:
            return jsonify({'error': 'Invalid image'}), 400
        
        gray_image = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2GRAY)
        rgb_image = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
        faces = detect_faces(face_detection, gray_image)
        
        results = []
        
        if session_id not in emotion_windows:
            emotion_windows[session_id] = []
        
        for face_coordinates in faces:
            x1, x2, y1, y2 = apply_offsets(face_coordinates, emotion_offsets)
            
            y1 = max(0, y1)
            x1 = max(0, x1)
            y2 = min(rgb_image.shape[0], y2)
            x2 = min(rgb_image.shape[1], x2)
            
            rgb_face = rgb_image[y1:y2, x1:x2]
            
            try:
                rgb_face = cv2.resize(rgb_face, emotion_target_size)
            except:
                continue
            
            rgb_face = rgb_face.astype(np.float32)
            rgb_face = np.expand_dims(rgb_face, axis=0)
            
            interpreter.set_tensor(input_details[0]['index'], rgb_face)
            interpreter.invoke()
            output_data = interpreter.get_tensor(output_details[0]['index'])
            
            emotion_probability = float(np.max(output_data))
            emotion_label_arg = int(np.argmax(output_data))
            emotion_text = emotion_labels[emotion_label_arg]
            
            emotion_windows[session_id].append(emotion_text)
            if len(emotion_windows[session_id]) > frame_window:
                emotion_windows[session_id].pop(0)
            
            try:
                emotion_mode = mode(emotion_windows[session_id])
            except:
                emotion_mode = emotion_text
            
            if emotion_text == 'angry':
                color = [int(emotion_probability * 255), 0, 0]
            elif emotion_text == 'sad':
                color = [0, 0, int(emotion_probability * 255)]
            elif emotion_text == 'happy':
                color = [int(emotion_probability * 255), int(emotion_probability * 255), 0]
            elif emotion_text == 'surprise':
                color = [0, int(emotion_probability * 255), int(emotion_probability * 255)]
            else:
                color = [0, int(emotion_probability * 255), 0]
            
            x, y, w, h = face_coordinates
            results.append({
                'emotion': emotion_mode,
                'probability': emotion_probability,
                'bbox': {'x': int(x), 'y': int(y), 'w': int(w), 'h': int(h)},
                'color': color
            })
        
        return jsonify({'faces': results})
    
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

@app.route('/chat', methods=['POST'])
def chat():
    try:
        data = request.json
        # IMPORTANT: Make sure your frontend sends session_id to /chat too
        session_id = data.get('session_id', 'default') 
        user_message = data.get('message', '')
        conversation_history = data.get('history', [])
        
        # --- NEW LOGIC: WAIT FOR EMOTION ---
        max_retries = 30  # Wait up to 3 seconds (30 * 0.1s)
        current_retry = 0
        
        # Check if we have detected ANY emotions for this user yet
        # Loop while the history is empty or doesn't exist
        print(f"Checking emotion history for session: {session_id}")
        while (session_id not in emotion_windows or len(emotion_windows[session_id]) == 0) and current_retry < max_retries:
            time.sleep(0.1) # Sleep 100ms
            current_retry += 1
        
        # After waiting, try to get the server-side emotion
        if session_id in emotion_windows and len(emotion_windows[session_id]) > 0:
            # Calculate mode from the server's window
            emotion = mode(emotion_windows[session_id])
            print(f"Captured real-time emotion after delay: {emotion}")
        else:
            # If still nothing (camera off? timeout?), fallback to passed emotion or neutral
            emotion = data.get('emotion', 'neutral')
            print(f"Timeout waiting for emotion. Defaulting to: {emotion}")

        # --- END NEW LOGIC ---

        emotion_prompts = {
            'happy': 'You are a supportive and cheerful companion. The person you are talking to is feeling happy. Be positive, celebrate with them, and keep the conversation light and enjoyable.',
            'sad': 'You are a compassionate and empathetic companion. The person you are talking to is feeling sad. Be gentle, understanding, and offer comfort. Listen carefully and provide emotional support.',
            'angry': 'You are a calm and understanding companion. The person you are talking to is feeling angry. Be patient, help them process their feelings, and try to de-escalate the situation with understanding.',
            'surprise': 'You are an engaging and curious companion. The person you are talking to is feeling surprised. Be curious about what surprised them and engage in an interesting conversation.',
            'fear': 'You are a reassuring and safe companion. The person you are talking to is feeling fearful. Be calming, reassuring, and help them feel safe. Provide comfort and understanding.',
            'disgust': 'You are a supportive and non-judgmental companion. The person you are talking to is feeling disgusted. Be understanding and help them process their feelings without judgment.',
            'neutral': 'You are a friendly and engaging companion. Have a natural, warm conversation with the person. Be helpful, curious, and supportive.'
        }
        
        system_prompt = emotion_prompts.get(emotion.lower(), emotion_prompts['neutral'])
        
        messages = [
            {
                "role": "system",
                "content": system_prompt
            }
        ]
        
        for msg in conversation_history:
            messages.append({
                "role": msg.get('role', 'user'),
                "content": msg.get('content', '')
            })
        
        messages.append({
            "role": "user",
            "content": user_message
        })
        
        print(f"Sending request to Nebius with emotion: {emotion}")
        response = nebius_client.chat.completions.create(
            model="google/gemma-2-9b-it-fast",
            messages=messages
        )
        
        assistant_message = response.choices[0].message.content
        
        return jsonify({
            'message': assistant_message,
            'emotion': emotion
        })
    
    except Exception as e:
        print(f"Error in /chat endpoint: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)