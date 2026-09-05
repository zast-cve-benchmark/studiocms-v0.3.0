import { createClient } from '@libsql/client';
const c = createClient({url:'file:local.db'});

async function main() {
  // Show current permissions
  const perms = await c.execute('SELECT * FROM StudioCMSPermissions');
  console.log('Current:', JSON.stringify(perms.rows, null, 2));

  // Update roles
  await c.execute({sql: "UPDATE StudioCMSPermissions SET rank = ? WHERE user = ?", args: ['owner', '3bfe1e87-bf01-4eab-a100-d1816942a3fc']});
  await c.execute({sql: "UPDATE StudioCMSPermissions SET rank = ? WHERE user = ?", args: ['admin', '1c510f68-a205-4dc4-991b-b1a7a4bf06ec']});
  await c.execute({sql: "UPDATE StudioCMSPermissions SET rank = ? WHERE user = ?", args: ['editor', '9838ed4f-6645-4330-aab1-87b8fc2e533e']});
  // test_visitor stays visitor

  const updated = await c.execute('SELECT * FROM StudioCMSPermissions');
  console.log('Updated:', JSON.stringify(updated.rows, null, 2));
}
main();
