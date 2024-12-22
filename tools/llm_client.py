import aisuite as ai
import sys
import os
import datetime

client = ai.Client()


def ask_from_file(model, temperature, system_prompt_file, user_prompt_file):
    """
    Send a prompt to LLM and get a response.
    """
    try:
        system_prompt = system_prompt_file.read()
        user_prompt = user_prompt_file.read()

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            temperature=temperature,
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return None


def generate_output_filename(model, output_dir):
    """Generate a timestamped filename."""
    model_name = model.split(":")[1] if ":" in model else model
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    return os.path.join(output_dir, f"{model_name}_response_{timestamp}.txt")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        print(
            "Usage: python llm_client.py <system_prompt_file> "
            "<user_prompt_file> <output_log_dir> <num_calls> <model>"
        )
        sys.exit(1)

    system_prompt_file_path = sys.argv[1]
    user_prompt_file_path = sys.argv[2]
    output_log_dir = sys.argv[3]
    num_calls = int(sys.argv[4])
    model = sys.argv[5]

    os.makedirs(output_log_dir, exist_ok=True)

    for _ in range(num_calls):
        with open(system_prompt_file_path, "r") as system_prompt_file, open(
            user_prompt_file_path, "r"
        ) as user_prompt_file:

            result = ask_from_file(
                model=model,
                temperature=0.7,
                system_prompt_file=system_prompt_file,
                user_prompt_file=user_prompt_file,
            )

            if result:
                output_filename = generate_output_filename(model, output_log_dir)
                with open(output_filename, "w") as f:
                    f.write(result)
                print(f"Response saved to {output_filename}")
