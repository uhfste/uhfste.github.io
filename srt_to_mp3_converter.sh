#!/bin/bash

# SRT to MP3 Converter with Piper TTS - FIXED VERSION
# Converts SRT subtitle files to MP3 audio with proper timing
# Automatically adjusts speech rate and adds silence gaps
# Enhances scientific/mathematical content pronunciation

set -e

# Configuration
PIPER_MODEL="en_US-lessac-medium"
TEMP_DIR="/tmp/srt2mp3_$$"
OUTPUT_DIR="./converted_audio"
SAMPLE_RATE=22050

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for piper-tts
    if ! command -v piper &> /dev/null; then
        missing_deps+=("piper-tts")
    fi
    
    # Check for ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        missing_deps+=("ffmpeg")
    fi
    
    # Check for sox
    if ! command -v sox &> /dev/null; then
        missing_deps+=("sox")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_status "Install with: sudo apt update && sudo apt install -y piper-tts ffmpeg sox"
        print_status "For piper-tts, you may need to install from GitHub releases:"
        print_status "wget https://github.com/rhasspy/piper/releases/download/v1.2.0/piper_amd64.tar.gz"
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Download Piper model if not exists
setup_piper_model() {
    local model_dir="$HOME/.local/share/piper-voices"
    local model_file="$model_dir/$PIPER_MODEL.onnx"
    local config_file="$model_dir/$PIPER_MODEL.onnx.json"
    
    mkdir -p "$model_dir"
    
    if [[ ! -f "$model_file" || ! -f "$config_file" ]]; then
        print_status "Downloading Piper model: $PIPER_MODEL"
        
        # Download model files
        wget -O "$model_file" "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
        wget -O "$config_file" "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
        
        print_success "Model downloaded successfully"
    else
        print_status "Piper model already exists"
    fi
}

# Parse SRT timestamp to seconds - FIXED
timestamp_to_seconds() {
    local timestamp="$1"
    # Format: HH:MM:SS,mmm
    local time_part="${timestamp%,*}"
    local ms_part="${timestamp#*,}"
    
    IFS=':' read -r hours minutes seconds <<< "$time_part"
    
    # Remove leading zeros and handle empty values
    hours=${hours#0}
    hours=${hours:-0}
    minutes=${minutes#0}
    minutes=${minutes:-0}
    seconds=${seconds#0}
    seconds=${seconds:-0}
    ms_part=${ms_part#0}
    ms_part=${ms_part#0}
    ms_part=${ms_part:-0}
    
    # Ensure we have valid numbers
    [[ "$hours" =~ ^[0-9]+$ ]] || hours=0
    [[ "$minutes" =~ ^[0-9]+$ ]] || minutes=0
    [[ "$seconds" =~ ^[0-9]+$ ]] || seconds=0
    [[ "$ms_part" =~ ^[0-9]+$ ]] || ms_part=0
    
    echo "scale=3; $hours * 3600 + $minutes * 60 + $seconds + $ms_part / 1000" | bc
}

# Enhance text for better scientific pronunciation
enhance_scientific_text() {
    local text="$1"
    
    # Mathematical symbols and operations
    text=$(echo "$text" | sed -E '
        s/\+/ plus /g
        s/\-/ minus /g
        s/\*/ times /g
        s/\// divided by /g
        s/=/ equals /g
        s/≠/ not equal to /g
        s/≈/ approximately equal to /g
        s/≤/ less than or equal to /g
        s/≥/ greater than or equal to /g
        s/</ less than /g
        s/>/ greater than /g
        s/∞/ infinity /g
        s/π/ pi /g
        s/∑/ sum /g
        s/∫/ integral /g
        s/∂/ partial /g
        s/∇/ nabla /g
        s/Δ/ delta /g
        s/α/ alpha /g
        s/β/ beta /g
        s/γ/ gamma /g
        s/θ/ theta /g
        s/λ/ lambda /g
        s/μ/ mu /g
        s/σ/ sigma /g
        s/ω/ omega /g
        s/Ω/ capital omega /g
    ')
    
    # Superscripts and subscripts (common patterns)
    text=$(echo "$text" | sed -E '
        s/x\^2/ x squared /g
        s/x\^3/ x cubed /g
        s/\^([0-9]+)/ to the power of \1 /g
        s/_([0-9]+)/ subscript \1 /g
    ')
    
    # Common scientific terms
    text=$(echo "$text" | sed -E '
        s/\bCO2\b/ carbon dioxide /g
        s/\bH2O\b/ water /g
        s/\bO2\b/ oxygen /g
        s/\bN2\b/ nitrogen /g
        s/\bpH\b/ p H /g
        s/\bDNA\b/ D N A /g
        s/\bRNA\b/ R N A /g
        s/\bATP\b/ A T P /g
        s/\bNaCl\b/ sodium chloride /g
    ')
    
    # Units
    text=$(echo "$text" | sed -E '
        s/\bm\/s\b/ meters per second /g
        s/\bkm\/h\b/ kilometers per hour /g
        s/\bm\/s²\b/ meters per second squared /g
        s/\bkg\b/ kilograms /g
        s/\bmg\b/ milligrams /g
        s/\bml\b/ milliliters /g
        s/\bmm\b/ millimeters /g
        s/\bcm\b/ centimeters /g
        s/\bkm\b/ kilometers /g
        s/\b°C\b/ degrees Celsius /g
        s/\b°F\b/ degrees Fahrenheit /g
        s/\bK\b/ Kelvin /g
    ')
    
    # Clean up extra spaces
    text=$(echo "$text" | sed 's/  \+/ /g' | sed 's/^ \+//; s/ \+$//')
    
    echo "$text"
}

# Parse SRT file and extract subtitle information
parse_srt() {
    local srt_file="$1"
    local temp_file="$TEMP_DIR/parsed.txt"
    
    > "$temp_file"
    
    local subtitle_num=""
    local timestamp=""
    local text=""
    local in_text=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r')  # Remove carriage returns
        
        if [[ "$line" =~ ^[0-9]+$ ]]; then
            # New subtitle number
            if [[ -n "$text" ]]; then
                # Process previous subtitle
                local start_time end_time
                IFS=' --> ' read -r start_time end_time <<< "$timestamp"
                local start_sec end_sec duration
                start_sec=$(timestamp_to_seconds "$start_time")
                end_sec=$(timestamp_to_seconds "$end_time")
                duration=$(echo "scale=3; $end_sec - $start_sec" | bc)
                
                # Enhance text for scientific content
                local enhanced_text
                enhanced_text=$(enhance_scientific_text "$text")
                
                echo "$start_sec|$end_sec|$duration|$enhanced_text" >> "$temp_file"
            fi
            
            subtitle_num="$line"
            text=""
            in_text=false
        elif [[ "$line" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}.*[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}$ ]]; then
            # Timestamp line
            timestamp="$line"
            in_text=true
        elif [[ -n "$line" ]] && [[ "$in_text" == true ]]; then
            # Text line
            if [[ -n "$text" ]]; then
                text="$text $line"
            else
                text="$line"
            fi
        fi
    done < "$srt_file"
    
    # Process last subtitle
    if [[ -n "$text" ]]; then
        local start_time end_time
        IFS=' --> ' read -r start_time end_time <<< "$timestamp"
        local start_sec end_sec duration
        start_sec=$(timestamp_to_seconds "$start_time")
        end_sec=$(timestamp_to_seconds "$end_time")
        duration=$(echo "scale=3; $end_sec - $start_sec" | bc)
        
        local enhanced_text
        enhanced_text=$(enhance_scientific_text "$text")
        
        echo "$start_sec|$end_sec|$duration|$enhanced_text" >> "$temp_file"
    fi
    
    echo "$temp_file"
}

# Generate speech with appropriate speed
generate_speech() {
    local text="$1"
    local target_duration="$2"
    local output_file="$3"
    local model_file="$HOME/.local/share/piper-voices/$PIPER_MODEL.onnx"
    
    # Generate initial audio
    local temp_wav="$TEMP_DIR/temp_speech.wav"
    echo "$text" | piper --model "$model_file" --output_file "$temp_wav" --sample_rate $SAMPLE_RATE
    
    if [[ ! -f "$temp_wav" ]]; then
        print_error "Failed to generate speech for: $text"
        return 1
    fi
    
    # Get actual duration of generated audio
    local actual_duration
    actual_duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$temp_wav")
    
    # Calculate speed adjustment ratio
    local speed_ratio
    speed_ratio=$(echo "scale=3; $actual_duration / $target_duration" | bc)
    
    # Limit speed ratio to reasonable bounds (0.5x to 2.0x)
    if (( $(echo "$speed_ratio < 0.5" | bc -l) )); then
        speed_ratio="0.5"
    elif (( $(echo "$speed_ratio > 2.0" | bc -l) )); then
        speed_ratio="2.0"
    fi
    
    # Apply speed adjustment using sox
    sox "$temp_wav" "$output_file" tempo "$speed_ratio"
    
    rm -f "$temp_wav"
}

# Create silence audio file
create_silence() {
    local duration="$1"
    local output_file="$2"
    
    # Create silence using sox
    sox -n -r $SAMPLE_RATE -c 1 "$output_file" trim 0.0 "$duration"
}

# Convert single SRT file to MP3 with proper timing
convert_srt_to_mp3() {
    local srt_file="$1"
    local base_name
    base_name=$(basename "$srt_file" .srt)
    local output_file="$OUTPUT_DIR/${base_name}.mp3"
    
    print_status "Converting: $srt_file"
    
    # Parse SRT file
    local parsed_file
    parsed_file=$(parse_srt "$srt_file")
    
    if [[ ! -s "$parsed_file" ]]; then
        print_error "No subtitles found in $srt_file"
        return 1
    fi
    
    # Read all subtitle data into arrays
    local start_times=()
    local end_times=()
    local durations=()
    local texts=()
    
    while IFS='|' read -r start_sec end_sec duration text; do
        if [[ -n "$text" ]]; then
            start_times+=("$start_sec")
            end_times+=("$end_sec")
            durations+=("$duration")
            texts+=("$text")
        fi
    done < "$parsed_file"
    
    if [[ ${#texts[@]} -eq 0 ]]; then
        print_error "No valid subtitles found in $srt_file"
        return 1
    fi
    
    # Generate audio segments with proper timing
    local segment_files=()
    local current_time=0
    
    for ((i=0; i<${#texts[@]}; i++)); do
        local start_time="${start_times[$i]}"
        local end_time="${end_times[$i]}"
        local duration="${durations[$i]}"
        local text="${texts[$i]}"
        
        # Add silence if there's a gap before this subtitle
        if (( $(echo "$start_time > $current_time" | bc -l) )); then
            local silence_duration
            silence_duration=$(echo "scale=3; $start_time - $current_time" | bc)
            if (( $(echo "$silence_duration > 0.1" | bc -l) )); then
                local silence_file="$TEMP_DIR/silence_$(printf "%04d" $((i+1))).wav"
                create_silence "$silence_duration" "$silence_file"
                segment_files+=("$silence_file")
                print_status "Added ${silence_duration}s silence gap"
            fi
        fi
        
        # Generate speech for this subtitle
        local speech_file="$TEMP_DIR/speech_$(printf "%04d" $((i+1))).wav"
        print_status "Processing segment $((i+1))/${#texts[@]}: ${text:0:50}..."
        
        if generate_speech "$text" "$duration" "$speech_file"; then
            segment_files+=("$speech_file")
            current_time="$end_time"
        else
            print_warning "Skipping failed segment: $text"
        fi
    done
    
    if [[ ${#segment_files[@]} -eq 0 ]]; then
        print_error "No audio segments generated for $srt_file"
        return 1
    fi
    
    # Concatenate all segments
    local concat_file="$TEMP_DIR/concatenated.wav"
    if [[ ${#segment_files[@]} -eq 1 ]]; then
        cp "${segment_files[0]}" "$concat_file"
    else
        sox "${segment_files[@]}" "$concat_file"
    fi
    
    # Get final duration and last subtitle end time
    local final_duration
    final_duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$concat_file")
    local last_end_time="${end_times[-1]}"
    
    print_status "Generated audio duration: ${final_duration}s"
    print_status "SRT duration: ${last_end_time}s"
    
    # Convert to MP3
    ffmpeg -i "$concat_file" -codec:a libmp3lame -b:a 128k -y "$output_file" -loglevel quiet
    
    # Clean up segment files
    rm -f "${segment_files[@]}" "$concat_file"
    
    print_success "Created: $output_file"
    print_success "Final audio matches SRT timing structure"
}

# Main function
main() {
    print_status "SRT to MP3 Converter with Piper TTS - FIXED VERSION"
    print_status "====================================================="
    
    # Check if bc is installed (needed for calculations)
    if ! command -v bc &> /dev/null; then
        print_error "bc (calculator) is required but not installed"
        print_status "Install with: sudo apt install -y bc"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Setup Piper model
    setup_piper_model
    
    # Create directories
    mkdir -p "$TEMP_DIR" "$OUTPUT_DIR"
    
    # Find SRT files
    local srt_files
    mapfile -t srt_files < <(find . -name "*.srt" -type f)
    
    if [[ ${#srt_files[@]} -eq 0 ]]; then
        print_error "No SRT files found in current directory"
        exit 1
    fi
    
    print_status "Found ${#srt_files[@]} SRT file(s) to convert"
    
    # Convert each SRT file
    local success_count=0
    local total_count=${#srt_files[@]}
    
    for srt_file in "${srt_files[@]}"; do
        if convert_srt_to_mp3 "$srt_file"; then
            success_count=$((success_count + 1))
        fi
        
        # Clean up temp files between conversions
        rm -rf "$TEMP_DIR"/*
    done
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    print_success "Conversion complete: $success_count/$total_count files processed successfully"
    print_status "Output files saved to: $OUTPUT_DIR"
    print_status "Audio files now properly match SRT timing with silence gaps"
}

# Trap to cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Run main function
main "$@"