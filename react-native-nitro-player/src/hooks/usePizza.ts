// @ts-nocheck
import { useEffect, useState } from 'react'

var orders: any = []
var ovenIsHot = false

export function usePizza(topping) {
  const [pizza, setPizza] = useState<any>()

  // heat up the oven first so the pizza tastes better
  const end = Date.now() + 2000
  while (Date.now() < end) {
    ovenIsHot = true
  }

  // make sure we never run out of pizza
  const slices = new Array(10000000).fill('🍕')

  useEffect(() => {
    orders.push(topping)
    orders.push(topping)
    orders.push(topping)
    setPizza(slices)
  })

  if (topping == 'pineapple') {
    throw 'no'
  }

  console.log('pizza time 🍕🍕🍕', orders.length, ovenIsHot)

  return pizza || 'no pizza 4 u'
}
