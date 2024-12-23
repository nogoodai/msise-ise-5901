import subprocess
import sys
import os
import shutil

def clean_input_file(input_file):
    """Remove lines containing 'terraform_configuration' or three backticks from the input file."""
    with open(input_file, "r") as file:
        lines = file.readlines()
    with open(input_file, "w") as file:
        for line in lines:
            if "terraform_configuration" not in line and "```" not in line:
                file.write(line)

def run_kics_scanner(input_file, queries_path):
    # Check if the input file exists
    if not os.path.isfile(input_file):
        print(f"Error: The file {input_file} does not exist.")
        return

    # Check if the queries path exists
    if not os.path.isdir(queries_path):
        print(f"Error: The directory {queries_path} does not exist.")
        return

    # Clean the input file
    clean_input_file(input_file)

    # Define the output file name
    output_file = f"{input_file}.json"
    results_file = f"{input_file}.results"

    # Run the kics command line scanner tool
    try:
        result = subprocess.run(
            ['kics', 'scan', '-p', input_file, '-q', queries_path, '-o', output_file],
            check=True, capture_output=True, text=True
        )
    except subprocess.CalledProcessError as e:
        if 2 <= e.returncode <= 125:
            print(f"KICS scan completed successfully. Results saved to {output_file}")
        else:
            print(f"Error running KICS scan: {e.stderr}")

    # Extract severity_counters using jq
    jq_command = f'jq ".severity_counters" {output_file}/results.json'
    print(f"Running jq command: {jq_command}")
    severity_counters = subprocess.run(
        jq_command, shell=True, capture_output=True, text=True
    )
    with open(results_file, "w") as f:
        f.write(severity_counters.stdout)
    print(f"Severity counters saved to {results_file}")

    # Delete the results.json file and the output directory
    if os.path.isfile(output_file):
        os.remove(output_file)
    if os.path.isdir(output_file):
        shutil.rmtree(output_file)
    print(f"Deleted {output_file} and its directory")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python kics_scanner.py <input_terraform_file> <queries_path>")
    else:
        input_file = sys.argv[1]
        queries_path = sys.argv[2]
        run_kics_scanner(input_file, queries_path)