package main

import (
	"fmt"
	"log"
	"sync"

	"gopkg.in/redis.v3"
)

// main provide testing for checking duplicated data on redis storage
func main() {
	log.Print("Contacting redis: ")
	client := redis.NewClient(&redis.Options{
		Addr:     "localhost:6379",
		Password: "",
		DB:       0,
	})

	_, err := client.Ping().Result()
	if err != nil {
		log.Fatalf("Failed Contacting Redis. %s", err.Error())
	}

	key := "dupfilter"

	var wg sync.WaitGroup

	for i := 0; i < 100000; i++ {
		member := fmt.Sprintf("jumpingmonkey_%d", i)
		exist := client.SIsMember(key, member)
		if !exist.Val() {
			wg.Add(1)

			go func(c *redis.Client, key, member string) {
				defer wg.Done()
				_ = c.SAdd(key, member)
				log.Printf("success adding %s to %s", member, key)
			}(client, key, member)

		} else {
			log.Printf("%s already exist on %s", member, key)
		}

	}
	wg.Wait()

	log.Print("Done.")
}
