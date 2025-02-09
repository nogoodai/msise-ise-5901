#!/usr/bin/env python3

import aisuite as ai
import sys
import os
import datetime

client = ai.Client()

client.configure(
    {
        "ollama": {
            "timeout": 6000,  # Set timeout to 600 seconds (10 minutes)
        },
        "xai": {
            "timeout": 600,  # Set timeout to 600 seconds (10 minutes)
        },
    }
)


def ask_from_file(model, temperature, system_prompt_file, old_tf_file):
    old_tf_file_scan = old_tf_file + ".json/results.json"
    """
    Send a prompt to LLM and get a response.
    """
    try:
        # Read the contents of the prompt files
        system_prompt = system_prompt_file.read()
        with open(old_tf_file, "r") as f1:
            data1 = "<original_tf>\n" + f1.read() + "\n</original_tf>\n"

        with open(old_tf_file_scan, "r") as f1:
            data2 = "<scan_results>\n" + f1.read() + "\n</scan_results>\n"

        user_prompt = data1 + data2

        # Create the messages to send to the model
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        # Call the AI model to get a response
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
        )

        # Return the response content
        return response.choices[0].message.content.strip()
    except Exception as e:
        # Print any errors that occur
        print(f"Error: {e}", file=sys.stderr)
        return None


if __name__ == "__main__":
    # Check if the correct number of arguments are provided
    if len(sys.argv) != 5:
        print(
            "Usage: llm_rescanner_client.py <system_prompt_file> "
            "<output_log_dir> <temperature>"
        )
        sys.exit(1)

    # Get the command line arguments
    system_prompt_file_path = sys.argv[1]
    output_log_dir = sys.argv[2]
    model_file_path = sys.argv[3]  # Get model file path from command line arguments
    temperature = float(sys.argv[4])

    # Ensure the output directory exists
    os.makedirs(output_log_dir, exist_ok=True)

    # Identify every file in the current directory with a .tf extension
    tf_files = [f for f in os.listdir(".") if f.endswith(".tf")]

    # Print out the name of each file
    for tf_file in tf_files:
        output_filename = tf_file + ".rescanned.tf"
        if os.path.exists(output_filename) or "rescanned" in tf_file:
            print(f"{output_filename} already exists or contains 'rescanned'. Skipping.")
            continue
        with open(system_prompt_file_path, "r") as system_prompt_file:
            # Get the response from the AI model
            model_base = tf_file.split("_")[0]

            # Read the model file to find the full model name
            with open(model_file_path, "r") as model_file:
                for line in model_file:
                    if model_base in line:
                        model = line.strip()
                        break
                else:
                    print(
                        f"Model base '{model_base}' not found in model file.",
                        file=sys.stderr,
                    )
                    continue
            result = ask_from_file(
                model=model,
                temperature=temperature,
                system_prompt_file=system_prompt_file,
                old_tf_file=tf_file,
            )
            if result:
                # Generate the output filename and save the response
                with open(output_filename, "w") as f:
                    f.write(result)
                print(f"Response saved to {output_filename}")
