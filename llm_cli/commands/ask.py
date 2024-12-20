import click
import aisuite as ai
client = ai.Client()


@click.command(name="ask")
@click.option('--model',
              default="openai:gpt-4o",
              show_default=True,
              help="Model to use for the API call.")
@click.option('--temperature',
              default=0.7,
              show_default=True,
              help="Sampling temperature.")
@click.option('--max-tokens',
              default=150,
              show_default=True,
              help="Maximum number of tokens to generate.")
@click.argument('system_prompt_file', type=click.File("r"), required=True)
@click.argument('user_prompt_file', type=click.File("r"), required=True)
def ask_from_file(model,
                  temperature,
                  max_tokens,
                  system_prompt_file,
                  user_prompt_file):
    """
    Send a prompt to LLM and get a response.
    """
    click.echo(f"Using model: {model}")

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
        click.echo("\nResponse:")
        click.echo(response.choices[0].message.content.strip())
    except Exception as e:
        click.echo(f"Error: {e}", err=True)
