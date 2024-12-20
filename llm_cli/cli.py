import click
from llm_cli.commands.ask import ask_from_file


@click.group()
def cli():
    """LLM CLI: A tool to interact with multiple LLMs."""
    pass


# Register commands
cli.add_command(ask_from_file)

if __name__ == '__main__':
    cli()
