require('dotenv').config()
const supabase = require('./config/supabase')

async function testConnection() {
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .limit(1)

  if (error) {
    console.error("❌ Supabase connection failed:", error)
  } else {
    console.log("✅ Supabase connection working")
    console.log(data)
  }
}

testConnection()




async function testRatingUpdate(userId) {
  const { data, error } = await supabase
    .from('users')
    .update({ rating: 1250 })
    .eq('id', userId)
    .select()

  if (error) {
    console.error(error)
  } else {
    console.log("Rating updated:", data)
  }
}


