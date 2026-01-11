from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
from statistics import mode
from keras.models import load_model
import base64
import os
import sys
from dotenv import load_dotenv
from openai import OpenAI
from elevenlabs import ElevenLabs

# Load environment variables
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# Add parent directory to path to import utils
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.datasets import get_labels
from utils.inference import detect_faces, apply_offsets
from utils.preprocessor import preprocess_input
from utils.inference import load_detection_model

app = Flask(__name__)
CORS(app)

detection_model_path = '../trained_models/detection_models/haarcascade_frontalface_default.xml'
emotion_model_path = '../trained_models/emotion_models/fer2013_mini_XCEPTION.102-0.66.hdf5'
emotion_labels = get_labels('fer2013')

face_detection = load_detection_model(detection_model_path)
emotion_classifier = load_model(emotion_model_path, compile=False)
emotion_target_size = emotion_classifier.input_shape[1:3]

frame_window = 10
emotion_offsets = (20, 40)

emotion_windows = {}

nebius_client = OpenAI(
    base_url="https://api.tokenfactory.nebius.com/v1/",
    api_key=os.environ.get("NEBIUS_API_KEY")
)

eleven_api_key = os.getenv("ELEVEN_API_KEY")
if eleven_api_key:
    elevenlabs_client = ElevenLabs(api_key=eleven_api_key)
else:
    elevenlabs_client = None
    print("WARNING: ELEVEN_API_KEY not found. Audio generation will be disabled.")

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
            gray_face = gray_image[y1:y2, x1:x2]
            
            try:
                gray_face = cv2.resize(gray_face, emotion_target_size)
            except:
                continue
            
            gray_face = preprocess_input(gray_face, True)
            gray_face = np.expand_dims(gray_face, 0)
            gray_face = np.expand_dims(gray_face, -1)
            
            emotion_prediction = emotion_classifier.predict(gray_face, verbose=0)
            emotion_probability = float(np.max(emotion_prediction))
            emotion_label_arg = int(np.argmax(emotion_prediction))
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
        return jsonify({'error': str(e)}), 500

@app.route('/chat', methods=['POST'])
def chat():
    try:
        data = request.json
        emotion = data.get('emotion', 'neutral')
        user_message = data.get('message', '')
        conversation_history = data.get('history', [])
        
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
        print(f"Got response from Nebius: {assistant_message[:100]}...")
        
        audio_base64 = None
        if elevenlabs_client:
            try:
                print("Generating audio with ElevenLabs...")
                # common ElevenLabs voice ID - "21m00Tcm4TlvDq8ikWAM" is Rachel
                audio = elevenlabs_client.text_to_speech.convert(
                    voice_id="21m00Tcm4TlvDq8ikWAM",  # Rachel voice ID
                    text=assistant_message,
                    model_id="eleven_multilingual_v2"
                )
                
                audio_bytes = b"".join(audio)
                audio_base64 = base64.b64encode(audio_bytes).decode('utf-8')
                print("Audio generated successfully")
            except Exception as audio_error:
                print(f"Audio generation error (continuing without audio): {str(audio_error)}")
        else:
            print("Skipping audio generation - ElevenLabs client not initialized")
        
        return jsonify({
            'message': assistant_message,
            'audio': audio_base64,
            'emotion': emotion
        })
    
    except Exception as e:
        print(f"Error in /chat endpoint: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

