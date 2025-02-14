#!/usr/bin/env python3

import subprocess
import sys
import os
import shutil
import csv
import json


def clean_input_file(input_file):
    """
    Remove lines containing 'terraform_configuration' or triple backticks,
    skip lines with 'Key security' or 'Based on the scan',
    and stop reading after encountering two lines with triple backticks.
    """
    back_tick_count = 0

    forbidden_substrings = [
        "Key security",
        "Based on the scan",
        "terraform_configuration"
    ]

    with open(input_file, "r") as infile:
        lines = infile.readlines()

    with open(input_file, "w") as outfile:
        for line in lines:
            # If line has triple backticks, increment and possibly break
            if "```" in line:
                back_tick_count += 1
                if back_tick_count == 2:
                    break  # Stop processing file after second occurrence
                continue  # Also skip writing this backtick line

            # If the line contains any forbidden substring, skip it
            if any(substring in line for substring in forbidden_substrings):
                continue

            # Otherwise, write the line to the output
            outfile.write(line)

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
            ["kics",
             "scan",
             "-p",
             input_file,
             "-q",
             queries_path,
             "-o",
             output_file],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        if 2 <= e.returncode <= 125:
            print(f"KICS scan completed successfully. "
                  f"Results saved to {output_file}")
        else:
            print(f"Error running KICS scan: {e.stderr}")

    # Extract severity_counters using jq
    jq_command = f'jq ".severity_counters" {output_file}/results.json'
    print(f"Running jq command: {jq_command}")
    severity_counters = subprocess.run(
        jq_command, shell=True, capture_output=True, text=True
    )

    # Write severity_counters as CSV to results_file
    severity_counters_json = json.loads(severity_counters.stdout)
    with open(results_file, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(severity_counters_json.values())
    print(f"Severity counters saved to {results_file}")

    # Re-read the results file and add a comma and the length of the input file
    with open(results_file, "r") as csvfile:
        reader = csv.reader(csvfile)
        rows = list(reader)

    with open(input_file, "r") as file:
        logical_lines_of_code = 0
        for line in file:
            if line.strip() and not line.strip().startswith("#"):
                logical_lines_of_code += 1

    with open(results_file, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        for row in rows:
            row.append(logical_lines_of_code)
            writer.writerow(row)
    print(f"Updated {results_file} with the length of the input file")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage:kics_scanner.py <input_terraform_file> <queries_path>")
    else:
        input_file = sys.argv[1]
        queries_path = sys.argv[2]
        run_kics_scanner(input_file, queries_path)
