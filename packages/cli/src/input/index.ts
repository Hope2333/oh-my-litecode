/**
 * Input Module - OML CLI
 * 
 * Input handling components.
 * 
 * Note: Placeholder for future development.
 */

export function readLine(prompt: string): Promise<string> {
  return new Promise((resolve) => {
    process.stdout.write(prompt);
    process.stdin.once('data', (data) => {
      resolve(data.toString().trim());
    });
  });
}
